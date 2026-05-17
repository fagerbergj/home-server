#!/usr/bin/env python3
"""
bench.py — measure real Ollama tok/s and layer placement, compare vs llmcalc predictions.

Usage:
  ./bench.py <ollama-blob-url> [<url> ...] [--ctxs 4096,16384,32768] [--api http://host:11434]

For each URL it fetches the model spec (same way llmcalc does), then for each
requested context size:
  1. Sends a warm-up generation to load the model at that ctx
  2. Sends a real generation, reads eval_count / eval_duration → real tok/s
  3. Reads /api/ps for size_vram → real GPU/CPU split
  4. Runs llmcalc.plan() for the same ctx → predicted tok/s + placement
And prints a side-by-side table.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request

from llmcalc import (
    fetch_blob, Model, plan, load_hardware,
    MIN_USABLE_TOK_S, WARN_TOK_S, CTX_LADDER,
)

LONG_PROMPT = (
    "Write a detailed technical essay (target around 800 words) about distributed "
    "systems. Cover the CAP theorem, common consensus algorithms (Paxos, Raft), "
    "consistency models (linearizable, sequential, causal, eventual), and give "
    "concrete real-world examples for each. Be specific and avoid filler."
)
TARGET_GEN = 300       # request at least this many tokens for a stable measurement
WARMUP_GEN = 8


class OllamaError(RuntimeError):
    """Carries the parsed Ollama error message from a non-2xx response."""


def http_post(url: str, body: dict, timeout: int = 600) -> dict:
    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )
    try:
        return json.loads(urllib.request.urlopen(req, timeout=timeout).read())
    except urllib.error.HTTPError as e:
        # Ollama returns JSON like {"error": "..."} for 4xx/5xx
        body_text = ""
        try:
            payload = json.loads(e.read().decode("utf-8", errors="replace"))
            body_text = payload.get("error", "") or json.dumps(payload)
        except Exception:
            body_text = "<no parseable body>"
        raise OllamaError(f"HTTP {e.code}: {body_text}") from None


def http_get(url: str, timeout: int = 10) -> dict:
    return json.loads(urllib.request.urlopen(url, timeout=timeout).read())


def generate(api: str, model: str, num_ctx: int, num_predict: int) -> dict:
    return http_post(f"{api}/api/generate", {
        "model": model,
        "prompt": LONG_PROMPT,
        "stream": False,
        "options": {"num_ctx": num_ctx, "num_predict": num_predict},
    })


def get_loaded(api: str, model: str) -> dict | None:
    ps = http_get(f"{api}/api/ps").get("models", [])
    return next((x for x in ps if x["name"] == model or x["model"] == model), None)


def model_exists(api: str, model: str) -> bool:
    """Check if a model is locally available via /api/show."""
    try:
        urllib.request.urlopen(
            urllib.request.Request(
                f"{api}/api/show",
                data=json.dumps({"name": model}).encode(),
                headers={"Content-Type": "application/json"},
            ),
            timeout=10,
        )
        return True
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return False
        raise


def ensure_pulled(api: str, model: str, container: str) -> None:
    """Pull the model via docker exec if it's not already present."""
    if model_exists(api, model):
        return
    print(f"  Model {model} not found locally — pulling...", flush=True)
    r = subprocess.run(
        ["docker", "exec", "-i", container, "ollama", "pull", model],
        check=False,
    )
    if r.returncode != 0:
        raise RuntimeError(f"failed to pull {model} (exit {r.returncode})")
    print(f"  ✓ pulled {model}")


def apply_context(model: str, ctx: int, container: str) -> None:
    """Recreate the model with a new num_ctx parameter."""
    modelfile = f"FROM {model}\nPARAMETER num_ctx {ctx}\n"
    r = subprocess.run(
        ["docker", "exec", "-i", container, "ollama", "create", model, "-f", "/dev/stdin"],
        input=modelfile.encode(), check=False,
    )
    if r.returncode != 0:
        raise RuntimeError(f"failed to apply num_ctx={ctx} (exit {r.returncode})")


def _report_failure(stage: str, ctx: int, err: Exception, api: str) -> None:
    """Print a useful error line for a failed warm-up/generate, with hints when possible."""
    msg = str(err)
    print(f"    ! {stage} failed at ctx={ctx}: {msg}")

    # Heuristic OOM detection — Ollama usually surfaces this in the error string
    low = msg.lower()
    if any(s in low for s in ("memory", "ggml_backend_alloc", "alloc", "cuda",
                              "out of memory", "model requires more system memory")):
        print(f"      → looks like out-of-memory at this context. Lower num_ctx, "
              f"use a smaller quant, or accept layer spill to RAM.")
    elif "timeout" in low:
        print(f"      → request timed out; the model may still be loading. "
              f"Try again, or pre-load with: docker exec ollama ollama run {{model}} ''")

    # Best-effort: pull the most recent error from server logs for additional context.
    # Only prints if docker is available AND the container exists.
    try:
        r = subprocess.run(
            ["docker", "logs", "--tail", "40", "ollama"],
            capture_output=True, text=True, timeout=5,
        )
        if r.returncode != 0:
            return
        relevant = [l for l in r.stderr.splitlines()
                    if any(k in l.lower() for k in ("error", "fail", "memory", "panic"))][-3:]
        for l in relevant:
            print(f"      log: {l.strip()[:200]}")
    except Exception:
        pass


def generate_vllm_stream(api: str, model: str, num_predict: int,
                         timeout: int = 600) -> tuple[float, int, float]:
    """Stream a completion from a vLLM OpenAI-compatible server. Returns
    (decode_seconds, completion_tokens, ttft_seconds). decode_seconds is
    measured first-token → last-token to match Ollama's eval_duration semantics
    (prompt processing excluded)."""
    body = {
        "model": model,
        "prompt": LONG_PROMPT,
        "max_tokens": num_predict,
        "temperature": 0.0,
        "stream": True,
        "stream_options": {"include_usage": True},
    }
    req = urllib.request.Request(
        f"{api}/v1/completions",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "Accept": "text/event-stream"},
    )
    t_start = time.time()
    t_first = None
    t_last = None
    completion_tokens = 0
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            for raw in resp:
                line = raw.decode("utf-8", errors="replace").strip()
                if not line.startswith("data:"):
                    continue
                payload = line[5:].strip()
                if payload == "[DONE]":
                    break
                try:
                    chunk = json.loads(payload)
                except json.JSONDecodeError:
                    continue
                choices = chunk.get("choices") or []
                if choices and choices[0].get("text"):
                    now = time.time()
                    if t_first is None:
                        t_first = now
                    t_last = now
                usage = chunk.get("usage")
                if usage and usage.get("completion_tokens"):
                    completion_tokens = usage["completion_tokens"]
    except urllib.error.HTTPError as e:
        body_text = e.read().decode("utf-8", errors="replace")[:300]
        raise OllamaError(f"HTTP {e.code}: {body_text}") from None

    if t_first is None or t_last is None:
        raise RuntimeError("no tokens received from vLLM")
    decode_s = max(t_last - t_first, 1e-6)
    ttft_s = t_first - t_start
    return decode_s, completion_tokens, ttft_s


def vllm_model_exists(api: str, model: str) -> bool:
    try:
        models = http_get(f"{api}/v1/models").get("data", [])
        return any(m.get("id") == model for m in models)
    except Exception:
        return False


def bench_vllm(model: str, api: str) -> tuple[str, list[dict]]:
    """vLLM is one-model-per-server with a fixed max_model_len, so there's no
    ctx ladder to sweep. Single warm-up + measurement, returned in the same
    row shape as bench_url (with prediction fields zeroed so print_table just
    shows '—' for them)."""
    if not vllm_model_exists(api, model):
        # vLLM lists models under whatever --served-model-name was passed.
        # Surface what it does have so the user can fix the name.
        try:
            listed = [m.get("id") for m in http_get(f"{api}/v1/models").get("data", [])]
            print(f"  ! vLLM doesn't serve '{model}'. Available: {listed}")
        except Exception as e:
            print(f"  ! couldn't reach vLLM at {api}: {e}")
        return model, []

    print(f"\n=== {model} (vLLM) ===")
    print(f"  warming up...", flush=True)
    try:
        generate_vllm_stream(api, model, WARMUP_GEN)
    except Exception as e:
        _report_failure("warm-up", 0, e, api)
        return model, []

    print(f"    measuring (target {TARGET_GEN} tokens)...", flush=True)
    try:
        decode_s, n_tok, ttft = generate_vllm_stream(api, model, TARGET_GEN)
    except Exception as e:
        _report_failure("generate", 0, e, api)
        return model, []

    real_tok_s = n_tok / decode_s if decode_s else 0
    print(f"    real: {real_tok_s:5.1f} t/s  ttft={ttft*1000:.0f}ms  "
          f"decode={decode_s:.2f}s  tokens={n_tok}")
    row = {
        "ctx": 0,  # vLLM ctx is fixed at server start (max_model_len)
        "pred_tok_s": 0, "real_tok_s": real_tok_s,
        "pred_vram": 0, "real_vram": 0,
        "pred_ram": 0, "real_ram": 0,
        "pred_layers_ram": 0, "real_layers_ram": 0,
        "blocks": 0,
        "wall_s": decode_s + ttft, "eval_count": n_tok,
        "ttft_s": ttft, "decode_s": decode_s,
    }
    return model, [row]


def score(r: dict) -> float:
    """ctx × tok/s — 'useful tokens-of-context processed per second'.
    This is naturally Pareto-optimal for the speed/context trade-off:
    it picks 16k over 2k when the speed loss is small, 131k over 262k
    when the speed loss is huge."""
    return r["ctx"] * r["real_tok_s"]


def recommend_ctx(rows: list[dict]) -> dict | None:
    """Best usable row by ctx × tok/s score."""
    usable = [r for r in rows if r["real_tok_s"] >= MIN_USABLE_TOK_S]
    return max(usable, key=score) if usable else None


def suggest_rerun(rows: list[dict], m: Model, url: str) -> str | None:
    """If the bench under- or over-shot the usable range, suggest a re-run with
    a different context band."""
    if not rows:
        return None
    smallest = min(r["ctx"] for r in rows)
    largest  = max(r["ctx"] for r in rows)

    all_too_slow    = all(r["real_tok_s"] < MIN_USABLE_TOK_S for r in rows)
    all_fast_enough = all(r["real_tok_s"] >= MIN_USABLE_TOK_S for r in rows)

    if all_too_slow and smallest > 4096:
        # Walk down the standard ladder to pick three smaller contexts
        smaller = [c for c in CTX_LADDER if c < smallest][-3:]
        if smaller:
            return (f"All tested contexts were below {MIN_USABLE_TOK_S} tok/s. "
                    f"Re-run with smaller contexts:\n"
                    f"      ./bench.py {url} --ctxs {','.join(str(c) for c in smaller)}")

    if all_fast_enough and (not m.ctx_max or largest < m.ctx_max):
        cap = m.ctx_max if m.ctx_max else CTX_LADDER[-1]
        bigger = [c for c in CTX_LADDER if largest < c <= cap][:3]
        if bigger:
            return (f"All tested contexts cleared {MIN_USABLE_TOK_S} tok/s with headroom. "
                    f"Re-run with larger contexts to find the cliff:\n"
                    f"      ./bench.py {url} --ctxs {','.join(str(c) for c in bigger)}")
    return None




def pick_ctxs(m: Model, hw, n: int = 3) -> list[int]:
    """Use llmcalc predictions to pick n contexts that bracket the recommendation:
    one step smaller (safe), the predicted recommended, one step larger (push the cliff)."""
    cap = m.ctx_max if m.ctx_max > 0 else CTX_LADDER[-1]
    ladder = sorted({c for c in CTX_LADDER if c <= cap} | ({m.ctx_max} if m.ctx_max else set()))
    plans = [(c, plan(m, hw, c)) for c in ladder]
    usable = [(c, p) for c, p in plans if p["tok_s"] >= MIN_USABLE_TOK_S
              and p["layers_unfit"] == 0]

    if not usable:
        # Nothing predicted as usable — pick the 3 with highest predicted tok/s
        plans.sort(key=lambda x: -x[1]["tok_s"])
        return sorted({c for c, _ in plans[:n]})

    rec_ctx = max(c for c, _ in usable)
    rec_idx = ladder.index(rec_ctx)
    picks = {rec_ctx}
    # one step smaller (safety)
    if rec_idx > 0:
        picks.add(ladder[rec_idx - 1])
    # one step larger (push the cliff)
    if rec_idx + 1 < len(ladder):
        picks.add(ladder[rec_idx + 1])
    # if we still need a 3rd (e.g. recommendation is already at the top), step further down
    if len(picks) < n and rec_idx > 1:
        picks.add(ladder[rec_idx - 2])
    return sorted(picks)[:n]


def model_from_prefilled(pf: dict) -> Model:
    return Model(
        name=pf["name"],
        file_gib=pf["file_gib"], quant_bits=pf["quant_bits"],
        embedding=pf["embedding"], blocks=pf["blocks"],
        kv_heads=pf.get("kv_heads", 0), kv_len=pf.get("kv_len", 128),
        arch=pf.get("arch", "transformer"),
        ctx_max=int(pf.get("ctx_max", 0)),
        attention_blocks=int(pf.get("attention_blocks", 0)),
        ssm_state_size=int(pf.get("ssm_state_size", 0)),
        ssm_inner_size=int(pf.get("ssm_inner_size", 0)),
        experts=int(pf.get("experts", 0)),
        experts_used=int(pf.get("experts_used", 0)),
        sliding_window=int(pf.get("sliding_window", 0)),
        swa_blocks=int(pf.get("swa_blocks", 0)),
        kv_len_swa=int(pf.get("kv_len_swa", 0)),
    )


def bench_url(url: str, ctxs: list[int] | None, api: str, hw, container: str) -> tuple[str, list[dict], Model]:
    pf = fetch_blob(url)
    m = model_from_prefilled(pf)
    ensure_pulled(api, m.name, container)
    if not ctxs:
        ctxs = pick_ctxs(m, hw, n=3)
        print(f"  Auto-picked contexts to bench: {ctxs}")
    extras = []
    if m.experts > 0:
        extras.append(f"MoE {m.experts_used}/{m.experts}")
    if m.arch == "ssm":
        extras.append(f"hybrid SSM {m.attention_blocks}/{m.blocks}")
    if m.sliding_window > 0 and m.swa_blocks > 0:
        extras.append(f"SWA {m.swa_blocks}/{m.blocks} window={m.sliding_window}")
    extra_str = ", " + ", ".join(extras) if extras else ""
    print(f"\n=== {m.name} ({m.file_gib:.1f} GiB Q{m.quant_bits}, {m.blocks} blocks{extra_str}) ===")

    rows = []
    for ctx in ctxs:
        if m.ctx_max and ctx > m.ctx_max:
            print(f"  skip ctx={ctx} (model max {m.ctx_max})")
            continue
        print(f"  ctx={ctx}: warming up...", flush=True)
        try:
            generate(api, m.name, ctx, WARMUP_GEN)
        except Exception as e:
            _report_failure("warm-up", ctx, e, api)
            continue

        print(f"    measuring (target {TARGET_GEN} tokens)...", flush=True)
        t0 = time.time()
        try:
            resp = generate(api, m.name, ctx, TARGET_GEN)
        except Exception as e:
            _report_failure("generate", ctx, e, api)
            continue
        wall = time.time() - t0

        eval_count = resp.get("eval_count", 0)
        eval_dur   = resp.get("eval_duration", 1)  # ns
        real_tok_s = eval_count / eval_dur * 1e9 if eval_dur else 0

        loaded = get_loaded(api, m.name) or {}
        size_total_b = loaded.get("size", 0)
        size_vram_b  = loaded.get("size_vram", 0)
        size_total = size_total_b / (1024 ** 3)
        size_vram  = size_vram_b  / (1024 ** 3)
        size_ram   = size_total - size_vram
        gpu_frac   = (size_vram_b / size_total_b) if size_total_b else 0
        real_layers_ram = round(m.blocks * (1 - gpu_frac))

        pred = plan(m, hw, ctx)
        rows.append({
            "ctx": ctx,
            "pred_tok_s": pred["tok_s"], "real_tok_s": real_tok_s,
            "pred_vram":  pred["vram"],  "real_vram":  size_vram,
            "pred_ram":   pred["ram"],   "real_ram":   size_ram,
            "pred_layers_ram": pred["layers_ram"], "real_layers_ram": real_layers_ram,
            "blocks": m.blocks,
            "wall_s": wall, "eval_count": eval_count,
        })
        r = rows[-1]
        print(f"    real: {real_tok_s:5.1f} t/s  vram={size_vram:.1f}G ram={size_ram:.1f}G "
              f"layers_ram={real_layers_ram}/{m.blocks}")
        print(f"    pred: {pred['tok_s']:5.1f} t/s  vram={pred['vram']:.1f}G ram={pred['ram']:.1f}G "
              f"layers_ram={pred['layers_ram']}/{m.blocks}")
    return m.name, rows, m


def print_table_vllm(model_results: list[tuple[str, list[dict]]]) -> None:
    print("\n" + "─" * 60)
    print(f"{'model':<32} {'tok/s':>7} {'ttft (ms)':>10} {'tokens':>7}")
    print("─" * 60)
    for name, rows in model_results:
        for r in rows:
            print(f"{name:<32} {r['real_tok_s']:>7.1f} "
                  f"{r.get('ttft_s', 0)*1000:>10.0f} {r['eval_count']:>7}")
    print("─" * 60)


def print_table(model_results: list[tuple[str, list[dict]]]) -> None:
    print("\n" + "─" * 92)
    print(f"{'model':<22} {'ctx':>7} {'pred t/s':>9} {'real t/s':>9} {'Δ':>6} "
          f"{'pred vram':>10} {'real vram':>10} {'pred RAM L':>11} {'real RAM L':>11}")
    print("─" * 92)
    for name, rows in model_results:
        for r in rows:
            delta = (r["real_tok_s"] - r["pred_tok_s"]) / r["pred_tok_s"] * 100 if r["pred_tok_s"] else 0
            print(f"{name:<22} {r['ctx']:>7} "
                  f"{r['pred_tok_s']:>9.1f} {r['real_tok_s']:>9.1f} {delta:>+5.0f}% "
                  f"{r['pred_vram']:>9.1f}G {r['real_vram']:>9.1f}G "
                  f"{r['pred_layers_ram']:>5}/{r['blocks']:<5} "
                  f"{r['real_layers_ram']:>5}/{r['blocks']:<5}")
    print("─" * 92)


def write_csv(path: str, model_results: list[tuple[str, list[dict]]]) -> None:
    import csv
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["model", "ctx", "pred_tok_s", "real_tok_s",
                    "pred_vram_gib", "real_vram_gib", "pred_ram_gib", "real_ram_gib",
                    "pred_layers_ram", "real_layers_ram", "blocks", "eval_count"])
        for name, rows in model_results:
            for r in rows:
                w.writerow([name, r["ctx"], f"{r['pred_tok_s']:.2f}", f"{r['real_tok_s']:.2f}",
                            f"{r['pred_vram']:.2f}", f"{r['real_vram']:.2f}",
                            f"{r['pred_ram']:.2f}", f"{r['real_ram']:.2f}",
                            r["pred_layers_ram"], r["real_layers_ram"],
                            r["blocks"], r["eval_count"]])
    print(f"\nWrote {path}")


def main():
    ap = argparse.ArgumentParser(description="Benchmark Ollama or vLLM (decode tok/s)")
    ap.add_argument("--backend", choices=["ollama", "vllm"], default="ollama",
                    help="Which inference server to talk to. ollama: pass blob URLs "
                         "(predictions + ctx sweep). vllm: pass served model names "
                         "(single measurement against /v1/completions).")
    ap.add_argument("urls", nargs="+",
                    help="Ollama: blob URLs from ollama.com. vLLM: served-model-name "
                         "(matches --served-model-name on the vllm server, default 'llama-70b').")
    ap.add_argument("--ctxs", default=None,
                    help="Ollama only. Comma-separated context sizes. "
                         "Default: auto-pick 3 around llmcalc's recommendation.")
    ap.add_argument("--api", default=None,
                    help="API URL. Defaults: ollama=http://localhost:11434, vllm=http://localhost:8000")
    ap.add_argument("--csv", help="Optional CSV output path")
    ap.add_argument("--container", default="ollama",
                    help="Ollama docker container name (for pull/apply)")
    ap.add_argument("--apply", action="store_true",
                    help="Apply a recommended context to the model after benchmarking. "
                         "Prompts you to pick when there are two candidates.")
    ap.add_argument("--yes", "-y", action="store_true",
                    help="Skip the apply prompt; use the speed-preferred default.")
    args = ap.parse_args()

    if args.api is None:
        args.api = "http://localhost:8000" if args.backend == "vllm" else "http://localhost:11434"

    if args.backend == "vllm":
        print(f"Backend: vLLM @ {args.api}")
        results = []
        for model in args.urls:
            try:
                name, rows = bench_vllm(model, args.api)
                if rows:
                    results.append((name, rows))
            except Exception as e:
                print(f"! {model}: {e}", file=sys.stderr)
        if results:
            print_table_vllm(results)
        return

    ctxs = [int(c.strip()) for c in args.ctxs.split(",") if c.strip()] if args.ctxs else None
    hw = load_hardware()
    per_gpu_vram = hw.vram_gib / hw.gpu_count
    per_gpu_bw   = hw.vram_bw_gbs / hw.gpu_count
    if hw.gpu_count > 1:
        gpu_str = (f"{hw.gpu_count}x {hw.gpu_name} {hw.vram_gib:.0f}G "
                   f"@ {hw.vram_bw_gbs:.0f}GB/s "
                   f"({per_gpu_vram:.0f}G×{hw.gpu_count} @ {per_gpu_bw:.0f}×{hw.gpu_count})")
    else:
        gpu_str = f"{hw.gpu_name} {hw.vram_gib:.0f}G @ {hw.vram_bw_gbs:.0f}GB/s"
    print(f"Hardware: {gpu_str} | RAM {hw.ram_gib:.0f}G @ {hw.ram_bw_gbs:.0f}GB/s | kv={hw.kv_cache_type}")

    results = []
    url_by_name: dict[str, str] = {}
    for url in args.urls:
        try:
            name, rows, m = bench_url(url, ctxs, args.api, hw, args.container)
            if rows:
                results.append((name, rows, m))
                url_by_name[name] = url
        except Exception as e:
            print(f"! {url}: {e}", file=sys.stderr)

    if results:
        # print_table / write_csv only need (name, rows) — strip the Model
        print_table([(n, r) for n, r, _ in results])
        if args.csv:
            write_csv(args.csv, [(n, r) for n, r, _ in results])

        for name, rows, m in results:
            recommended = recommend_ctx(rows)
            url = url_by_name.get(name, "<url>")
            hint = suggest_rerun(rows, m, url)

            if not recommended:
                print(f"\n→ {name}: no context met the {MIN_USABLE_TOK_S} tok/s usability threshold.")
                if hint:
                    print(f"  → {hint}")
                continue

            usable = sorted(
                [r for r in rows if r["real_tok_s"] >= MIN_USABLE_TOK_S],
                key=lambda r: r["ctx"],
            )
            print(f"\n→ {name}: usable contexts (best score = ctx × tok/s):")
            for r in usable:
                marker = "  ← recommended" if r is recommended else ""
                print(f"    num_ctx={r['ctx']:>7}  {r['real_tok_s']:>5.1f} tok/s  "
                      f"{r['real_layers_ram']:>2}/{r['blocks']} layers in RAM  "
                      f"score={score(r):>10,.0f}{marker}")

            apply_target = recommended
            if args.apply:
                if len(usable) > 1 and not args.yes:
                    options = ", ".join(str(r["ctx"]) for r in usable)
                    raw = input(
                        f"  Apply which num_ctx? [{recommended['ctx']}] "
                        f"(choices: {options}, or 'n' to skip): "
                    ).strip().lower()
                    if raw in ("n", "none", "skip"):
                        apply_target = None
                    elif raw:
                        try:
                            picked = int(raw)
                            apply_target = next((r for r in usable if r["ctx"] == picked), None)
                            if not apply_target:
                                print(f"  ! {picked} isn't in the usable set — skipping.")
                        except ValueError:
                            print(f"  ! couldn't parse '{raw}' — skipping.")
                            apply_target = None
                if apply_target:
                    print(f"  Applying num_ctx={apply_target['ctx']}...", flush=True)
                    try:
                        apply_context(name, apply_target["ctx"], args.container)
                        print(f"  ✓ {name} now uses num_ctx={apply_target['ctx']}")
                    except Exception as e:
                        print(f"  ! apply failed: {e}", file=sys.stderr)
                else:
                    print(f"  (skipped)")
            else:
                print(f"  Apply with:  ./bench.py ... --apply")
                print(f"  Or manually: docker exec -i {args.container} bash -c "
                      f"'printf \"FROM {name}\\nPARAMETER num_ctx {recommended['ctx']}\" "
                      f"| ollama create {name} -f /dev/stdin'")

            if hint:
                print(f"  → {hint}")


if __name__ == "__main__":
    main()
