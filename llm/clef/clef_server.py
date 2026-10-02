"""Clef /v1/systemone server for the 3090, built on Cloudflare's own inference code (joint_schema_model.py in the
checkpoint). One model thread; concurrent requests arriving within --window-ms are batched through collate_records.
usage: clef_server.py --model /models/clef --port 8013 [--max-input-tokens 8192] [--max-batch 8] [--window-ms 5]"""
import argparse, asyncio, json, sys, threading, time
from pathlib import Path

import torch
import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

import quant

ap = argparse.ArgumentParser()
ap.add_argument("--model", required=True); ap.add_argument("--port", type=int, default=8013); ap.add_argument("--host", default="127.0.0.1")
ap.add_argument("--max-input-tokens", type=int, default=8192, help="16384 peaks ~15 GB, which OOMs beside the embedder plus a Plex NVDEC transcode"); ap.add_argument("--max-batch", type=int, default=8)
ap.add_argument("--max-batch-tokens", type=int, default=4096, help="padded tokens per batch; larger batches are compute-bound on the 3090 and only add queueing")
ap.add_argument("--window-ms", type=float, default=5.0)
a = ap.parse_args()
sys.path.insert(0, a.model)
import joint_schema_model as jsm   # noqa: E402  (ships with the checkpoint)
from safetensors.torch import load_file   # noqa: E402
from transformers import AutoProcessor, Qwen3_5ForConditionalGeneration   # noqa: E402

t0 = time.time()
bb = Qwen3_5ForConditionalGeneration.from_pretrained(a.model, dtype=torch.bfloat16, device_map={"": "cpu"})   # mmapped
bb.config.use_cache = False
if hasattr(bb.model, "visual"): bb.model.visual = None   # text-only service; the vision tower is never loaded onto the GPU
lm = bb.model.language_model
lm.embed_tokens = quant.CpuEmbedding(quant.CpuRowInt8(lm.embed_tokens.weight))
bb.lm_head = quant.CpuHead(quant.CpuRowInt8(bb.lm_head.weight))
n_q = quant.quantize(lm)
bb.to("cuda")
head = jsm.JointSchemaHead(**json.loads((Path(a.model) / "joint_head_config.json").read_text()))
head.load_state_dict(load_file(Path(a.model) / "joint_head.safetensors"), strict=True)
head = head.to("cuda", torch.bfloat16)
processor = AutoProcessor.from_pretrained(a.model)
model = jsm.ClefModel(bb, head).eval()
PAD = processor.tokenizer.pad_token_id
t_w = time.time()
with torch.inference_mode():
    # compile the fused dequant for every weight shape, and let fla's Triton kernels autotune for each length bucket now:
    # an untuned bucket costs ~10 s on its first request (measured at ~2k tokens)
    for n in (16, 512, 1024, 2048, 4096, 8192, min(16384, a.max_input_tokens)):
        if n > a.max_input_tokens: break
        warm = {"model": "warmup", "state": "warm " * n, "questions": {"w": {"type": "noul", "instructions": "Is this a warm-up?"}}}
        model(jsm.collate_records([jsm.encode_record(processor.tokenizer, warm, max_length=n + 512, processor=processor)], PAD, torch.device("cuda")))
    torch.cuda.empty_cache()
torch.cuda.synchronize()
LOAD_S = time.time() - t0
print(f"clef loaded in {LOAD_S:.0f}s (warm-up/compile {time.time() - t_w:.0f}s): {n_q} linears int4, cuda {torch.cuda.memory_allocated() / 2**30:.2f} GiB", flush=True)


class Job:
    __slots__ = ("req", "enc", "fut", "loop", "t")


queue: "asyncio.Queue[Job]" = None
lock = threading.Lock()


def run_batch(jobs):
    """Model thread: one forward over the batch; -> per job (answers, input_tokens)."""
    with lock, torch.inference_mode():
        logits = model(jsm.collate_records([j.enc for j in jobs], PAD, torch.device("cuda")))
    out = []
    for j, rec_logits in zip(jobs, logits):
        qs = j.req["questions"]
        answers = {q.question_id: jsm.systemone_answer(qs[q.question_id], dict(zip(q.option_ids, l.float().softmax(-1).tolist())))
                   for q, l in zip(j.enc.questions, rec_logits)}
        out.append((answers, len(j.enc.input_ids)))
    return out


async def batcher():
    loop = asyncio.get_running_loop()
    while True:
        jobs = [await queue.get()]
        deadline = loop.time() + a.window_ms / 1000
        while len(jobs) < a.max_batch:
            tokens = max(len(j.enc.input_ids) for j in jobs) * (len(jobs) + 1)
            if tokens > a.max_batch_tokens: break
            try: jobs.append(await asyncio.wait_for(queue.get(), max(0.0, deadline - loop.time())))
            except asyncio.TimeoutError: break
        t = time.perf_counter()
        try:
            results = await loop.run_in_executor(None, run_batch, jobs)
            ms = (time.perf_counter() - t) * 1000
            for j, (answers, n) in zip(jobs, results):
                j.fut.set_result({"model": j.req["model"], "answers": answers, "usage": {"input_tokens": n, "output_tokens": 0},
                                  "latency_ms": round(ms, 1), "batch_size": len(jobs)})
        except Exception as e:   # every request of the failed batch gets the error; the batcher lives on
            for j in jobs:
                if not j.fut.done(): j.fut.set_exception(e)


app = FastAPI(title="clef")


@app.on_event("startup")
async def start():
    global queue
    queue = asyncio.Queue()
    asyncio.get_running_loop().create_task(batcher())


@app.get("/health")
def health():
    return {"status": "ok", "load_s": round(LOAD_S), "cuda_alloc_gib": round(torch.cuda.memory_allocated() / 2**30, 2)}


@app.get("/v1/models")
def models():
    return {"models": [{"name": "clef", "quant": "int4 g128 RTN (compiled dequant + cuBLAS), int8 embedding rows in host RAM", "max_input_tokens": a.max_input_tokens}]}


@app.post("/v1/systemone")
async def systemone(req: Request):
    body = await req.json()
    qs = body.get("questions")
    if not isinstance(body.get("model"), str) or "state" not in body: return JSONResponse({"detail": "model and state are required"}, 422)
    if not isinstance(qs, dict) or not qs: return JSONResponse({"detail": "at least one question is required"}, 422)
    for qid, q in qs.items():
        if q.get("type") not in jsm.QUESTION_TYPES: return JSONResponse({"detail": f"{qid}: type must be noul, choice, or score"}, 422)
        if q["type"] != "noul" and not q.get("criteria"): return JSONResponse({"detail": f"{qid}: criteria must not be empty"}, 422)
    try:
        enc = jsm.encode_record(processor.tokenizer, body, max_length=10 ** 7, processor=processor)   # untruncated, to enforce the cap honestly
    except ValueError as e:
        return JSONResponse({"detail": str(e)}, 422)
    if len(enc.input_ids) > a.max_input_tokens:
        return JSONResponse({"detail": f"input is {len(enc.input_ids)} tokens; this server accepts at most {a.max_input_tokens}"}, 413)
    j = Job(); j.req, j.enc, j.fut = body, enc, asyncio.get_running_loop().create_future()
    await queue.put(j)
    try:
        return await j.fut
    except torch.cuda.OutOfMemoryError:
        torch.cuda.empty_cache()
        return JSONResponse({"detail": "out of GPU memory for this batch; retry or shorten the input"}, 503)


uvicorn.run(app, host=a.host, port=a.port)
