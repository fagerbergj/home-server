"""GPU worker: one-shot subprocess for pyannote inference.

Spawned by app.py per request. Exits when done so the HIP context (and
its persistent KFD event-wait thread, which busy-polls one CPU core
indefinitely) dies with the process.

Protocol: invoked as `python3 gpu_worker.py {diarize|embed}`. Reads a
JSON task from stdin, writes a JSON result to stdout. Log lines go to
stderr so they don't corrupt the result.
"""
from __future__ import annotations

import json
import os
import sys

import numpy as np
import soundfile as sf
import torch
from pyannote.audio import Inference, Pipeline
from pyannote.core import Segment

DEVICE = os.environ.get("DEVICE", "cuda")
HF_TOKEN = os.environ.get("HF_TOKEN")


def _log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def _load_audio_dict(wav_path: str) -> dict:
    """See app.py history: pyannote 3.4's torchcodec dlopen-fails on ROCm
    torch. Passing a {'waveform', 'sample_rate'} dict bypasses it."""
    data, sr = sf.read(wav_path, dtype="float32", always_2d=False)
    if data.ndim == 1:
        waveform = torch.from_numpy(data).unsqueeze(0)
    else:
        waveform = torch.from_numpy(data.T).contiguous()
    return {"waveform": waveform, "sample_rate": sr}


def _cosine(a, b) -> float:
    av = np.asarray(a, dtype=np.float32).flatten()
    bv = np.asarray(b, dtype=np.float32).flatten()
    denom = float(np.linalg.norm(av) * np.linalg.norm(bv)) + 1e-10
    return float(np.dot(av, bv) / denom)


def _match_voiceprint(
    embedding, voiceprints: dict, threshold: float
) -> tuple[str, float] | None:
    best_name, best_sim = None, 0.0
    for name, embs in voiceprints.items():
        for e in embs:
            sim = _cosine(embedding, e)
            if sim > best_sim:
                best_sim = sim
                best_name = name
    if best_name and best_sim >= threshold:
        return best_name, best_sim
    return None


def _device() -> torch.device:
    return torch.device("cuda") if DEVICE == "cuda" else torch.device("cpu")


def cmd_diarize(task: dict) -> list[dict]:
    wav_path = task["wav_path"]
    diarization_model = task["diarization_model"]
    embedding_model = task["embedding_model"]
    min_speakers = task["min_speakers"]
    max_speakers = task["max_speakers"]
    voiceprints = task.get("voiceprints") or {}
    min_enroll_seg_sec = task["min_enroll_seg_sec"]
    speaker_match_threshold = task["speaker_match_threshold"]

    _log(f"loading diarization pipeline={diarization_model}")
    pipeline = Pipeline.from_pretrained(diarization_model, token=HF_TOKEN)
    if pipeline is None:
        raise RuntimeError(
            f"Pipeline.from_pretrained returned None — check HF_TOKEN and that "
            f"you've accepted the {diarization_model} license on huggingface.co."
        )
    if DEVICE == "cuda":
        pipeline.to(torch.device("cuda"))

    audio = _load_audio_dict(wav_path)
    diarization = pipeline(
        audio, min_speakers=min_speakers, max_speakers=max_speakers
    )
    # pyannote 3.4 wraps the Annotation in a DiarizeOutput dataclass.
    annotation = getattr(diarization, "speaker_diarization", diarization)

    segs: list[dict] = []
    for turn, _, speaker in annotation.itertracks(yield_label=True):
        segs.append(
            {
                "start": float(turn.start),
                "end": float(turn.end),
                "speaker": speaker,
            }
        )
    segs.sort(key=lambda s: s["start"])
    del pipeline

    if not voiceprints or not segs:
        return segs

    inference = Inference(
        embedding_model, window="whole", token=HF_TOKEN, device=_device()
    )

    by_speaker: dict[str, list[dict]] = {}
    for s in segs:
        by_speaker.setdefault(s["speaker"], []).append(s)

    relabel: dict[str, str] = {}
    for speaker, sps in by_speaker.items():
        longest = max(sps, key=lambda s: s["end"] - s["start"])
        dur = longest["end"] - longest["start"]
        if dur < min_enroll_seg_sec:
            _log(
                f"voiceprint: skip {speaker}, longest segment "
                f"{dur:.2f}s < {min_enroll_seg_sec:.2f}s"
            )
            continue
        try:
            emb = inference.crop(audio, Segment(longest["start"], longest["end"]))
            emb_list = np.asarray(emb).flatten().tolist()
        except Exception as e:
            _log(f"voiceprint: embedding failed for {speaker}: {e}")
            continue
        match = _match_voiceprint(emb_list, voiceprints, speaker_match_threshold)
        if match:
            name, sim = match
            _log(f"voiceprint: {speaker} -> {name} (sim={sim:.3f})")
            relabel[speaker] = name
        else:
            _log(
                f"voiceprint: no match for {speaker} above threshold "
                f"{speaker_match_threshold:.2f}"
            )

    if relabel:
        for s in segs:
            if s["speaker"] in relabel:
                s["speaker"] = relabel[s["speaker"]]

    return segs


def cmd_embed(task: dict) -> list[float]:
    wav_path = task["wav_path"]
    embedding_model = task["embedding_model"]
    inference = Inference(
        embedding_model, window="whole", token=HF_TOKEN, device=_device()
    )
    audio = _load_audio_dict(wav_path)
    emb = inference(audio)
    return np.asarray(emb).flatten().tolist()


def main() -> None:
    if torch.version.hip is None:
        raise SystemExit(
            f"torch {torch.__version__} is not a ROCm build "
            f"(torch.version.hip is None, cuda={torch.version.cuda})."
        )
    if len(sys.argv) != 2:
        raise SystemExit("usage: gpu_worker.py {diarize|embed}")
    cmd = sys.argv[1]
    task = json.loads(sys.stdin.read())
    if cmd == "diarize":
        result = cmd_diarize(task)
    elif cmd == "embed":
        result = cmd_embed(task)
    else:
        raise SystemExit(f"unknown command: {cmd}")
    sys.stdout.write(json.dumps(result))


if __name__ == "__main__":
    main()
