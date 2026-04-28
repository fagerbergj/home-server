"""FastAPI wrapper: faster-whisper transcription + NeMo speaker diarization.

Endpoint matches the OpenAI /v1/audio/transcriptions shape that the existing
document-pipeline Go client already speaks. Returns:
    {"text": "[SPEAKER_00] hello there\n\n[SPEAKER_01] hi"}

Models load per request and unload before returning so VRAM is freed between
calls — the GPU is shared with Ollama in this setup.
"""
from __future__ import annotations

import gc
import json
import logging
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

import torch
from fastapi import FastAPI, Form, UploadFile
from faster_whisper import WhisperModel
from omegaconf import OmegaConf

DEVICE = os.environ.get("DEVICE", "cuda")
COMPUTE_TYPE = os.environ.get("COMPUTE_TYPE", "float16")
DEFAULT_WHISPER_MODEL = os.environ.get(
    "DEFAULT_WHISPER_MODEL", "Systran/faster-whisper-large-v3"
)
MAX_NUM_SPEAKERS = int(os.environ.get("MAX_NUM_SPEAKERS", "8"))

app = FastAPI()
logger = logging.getLogger("uvicorn.error")


def _free():
    gc.collect()
    if DEVICE == "cuda":
        torch.cuda.empty_cache()


def _to_mono16k(src: str) -> str:
    """NeMo expects 16 kHz mono wav. Convert via ffmpeg."""
    dst = src + ".16k.wav"
    subprocess.run(
        ["ffmpeg", "-y", "-i", src, "-ar", "16000", "-ac", "1", dst],
        check=True, capture_output=True,
    )
    return dst


def _diarize(wav_path: str, work_dir: str) -> list[dict]:
    """Run NeMo NeuralDiarizer; return list of {start, end, speaker} segments."""
    # Lazy-import — NeMo is heavy.
    from nemo.collections.asr.models.msdd_models import NeuralDiarizer

    manifest_path = os.path.join(work_dir, "manifest.json")
    with open(manifest_path, "w") as f:
        json.dump({
            "audio_filepath": wav_path,
            "offset": 0,
            "duration": None,
            "label": "infer",
            "text": "-",
            "rttm_filepath": None,
            "uem_filepath": None,
        }, f)
        f.write("\n")

    cfg = OmegaConf.create({
        "diarizer": {
            "manifest_filepath": manifest_path,
            "out_dir": work_dir,
            "oracle_vad": False,
            "collar": 0.25,
            "ignore_overlap": True,
            "vad": {
                "model_path": "vad_multilingual_marblenet",
                "parameters": {
                    "onset": 0.8, "offset": 0.6,
                    "pad_onset": 0.05, "pad_offset": -0.1,
                    "min_duration_on": 0.2, "min_duration_off": 0.2,
                },
            },
            "speaker_embeddings": {
                "model_path": "titanet_large",
                "parameters": {
                    "window_length_in_sec": [1.5, 1.25, 1.0, 0.75, 0.5],
                    "shift_length_in_sec":  [0.75, 0.625, 0.5, 0.375, 0.25],
                    "multiscale_weights":   [1, 1, 1, 1, 1],
                    "save_embeddings": False,
                },
            },
            "clustering": {
                "parameters": {
                    "oracle_num_speakers": False,
                    "max_num_speakers": MAX_NUM_SPEAKERS,
                    "enhanced_count_thres": 80,
                    "max_rp_threshold": 0.25,
                    "sparse_search_volume": 30,
                },
            },
            "msdd_model": {
                "model_path": "diar_msdd_telephonic",
                "parameters": {
                    "use_speaker_model_from_ckpt": True,
                    "infer_batch_size": 25,
                    "sigmoid_threshold": [0.7],
                    "seq_eval_mode": False,
                    "split_infer": True,
                    "diar_window_length": 50,
                    "overlap_infer_spk_limit": 5,
                },
            },
        },
        "num_workers": 1,
        "sample_rate": 16000,
        "batch_size": 64,
        "device": DEVICE,
        "verbose": False,
    })

    diarizer = NeuralDiarizer(cfg=cfg)
    diarizer.diarize()
    del diarizer

    stem = Path(wav_path).stem
    rttm = Path(work_dir) / "pred_rttms" / f"{stem}.rttm"
    segs: list[dict] = []
    if rttm.exists():
        for line in rttm.read_text().splitlines():
            # Format: SPEAKER <stem> 1 <start> <dur> <NA> <NA> <speaker> <NA> <NA>
            parts = line.split()
            if len(parts) < 8 or parts[0] != "SPEAKER":
                continue
            start = float(parts[3])
            dur = float(parts[4])
            segs.append({"start": start, "end": start + dur, "speaker": parts[7]})
    segs.sort(key=lambda s: s["start"])
    return segs


def _assign_speakers(words: list[dict], segs: list[dict]) -> list[dict]:
    """Pick the speaker whose RTTM segment overlaps each word most."""
    out = []
    for w in words:
        best, best_overlap = None, 0.0
        for s in segs:
            ov = max(0.0, min(w["end"], s["end"]) - max(w["start"], s["start"]))
            if ov > best_overlap:
                best_overlap = ov
                best = s["speaker"]
        out.append({**w, "speaker": best or "SPEAKER_??"})
    return out


def _format(words: list[dict]) -> str:
    """Group consecutive words by speaker into one paragraph each."""
    if not words:
        return ""
    lines: list[str] = []
    cur_speaker = words[0]["speaker"]
    cur: list[str] = [words[0]["word"]]
    for w in words[1:]:
        if w["speaker"] != cur_speaker:
            lines.append(f"[{cur_speaker}]" + "".join(cur).rstrip())
            cur_speaker = w["speaker"]
            cur = [w["word"]]
        else:
            cur.append(w["word"])
    lines.append(f"[{cur_speaker}]" + "".join(cur).rstrip())
    return "\n\n".join(lines)


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/v1/audio/transcriptions")
async def transcribe(file: UploadFile, model: str = Form(DEFAULT_WHISPER_MODEL)):
    suffix = os.path.splitext(file.filename or "audio.webm")[1] or ".webm"
    work_dir = tempfile.mkdtemp(prefix="diar-")
    upload_path = os.path.join(work_dir, "upload" + suffix)
    with open(upload_path, "wb") as f:
        f.write(await file.read())

    try:
        wav_path = _to_mono16k(upload_path)

        logger.info("transcribing model=%s", model)
        whisper = WhisperModel(model, device=DEVICE, compute_type=COMPUTE_TYPE)
        segments, _ = whisper.transcribe(wav_path, word_timestamps=True)
        words: list[dict] = []
        for seg in segments:
            for w in (seg.words or []):
                words.append({
                    "start": float(w.start),
                    "end": float(w.end),
                    "word": w.word,
                })
        del whisper
        _free()

        logger.info("diarizing")
        speaker_segs = _diarize(wav_path, work_dir)
        _free()

        words = _assign_speakers(words, speaker_segs)
        return {"text": _format(words)}
    finally:
        shutil.rmtree(work_dir, ignore_errors=True)
        _free()
