"""FastAPI wrapper: faster-whisper transcription + pyannote speaker diarization.

Endpoint matches the OpenAI /v1/audio/transcriptions shape that the existing
document-pipeline Go client already speaks. Returns:
    {"text": "[SPEAKER_00] hello there\\n\\n[SPEAKER_01] hi"}

Models load per request and unload before returning so VRAM is freed between
calls — the GPU is shared with Ollama in this setup.
"""
from __future__ import annotations

import gc
import logging
import os
import shutil
import subprocess
import tempfile

import torch
from fastapi import FastAPI, Form, HTTPException, UploadFile
from faster_whisper import WhisperModel

DEVICE = os.environ.get("DEVICE", "cuda")
COMPUTE_TYPE = os.environ.get("COMPUTE_TYPE", "float16")
DEFAULT_WHISPER_MODEL = os.environ.get(
    "DEFAULT_WHISPER_MODEL", "Systran/faster-whisper-large-v3"
)
DIARIZATION_MODEL = os.environ.get(
    "DIARIZATION_MODEL", "pyannote/speaker-diarization-3.1"
)
HF_TOKEN = os.environ.get("HF_TOKEN")
MIN_SPEAKERS = int(os.environ.get("MIN_SPEAKERS", "1"))
MAX_SPEAKERS = int(os.environ.get("MAX_SPEAKERS", "8"))

app = FastAPI()
logger = logging.getLogger("uvicorn.error")


def _free():
    gc.collect()
    if DEVICE == "cuda":
        torch.cuda.empty_cache()


def _to_mono16k(src: str, dst_dir: str) -> str:
    """pyannote prefers 16 kHz mono wav; ffmpeg-convert."""
    dst = os.path.join(dst_dir, "audio.16k.wav")
    subprocess.run(
        ["ffmpeg", "-y", "-i", src, "-ar", "16000", "-ac", "1", dst],
        check=True, capture_output=True,
    )
    return dst


def _diarize(wav_path: str) -> list[dict]:
    """Run pyannote diarization. Returns list of {start, end, speaker}."""
    # Lazy-import — pyannote pulls torch + heavy deps.
    from pyannote.audio import Pipeline

    logger.info("loading diarization pipeline=%s", DIARIZATION_MODEL)
    pipeline = Pipeline.from_pretrained(DIARIZATION_MODEL, use_auth_token=HF_TOKEN)
    if pipeline is None:
        raise RuntimeError(
            f"Pipeline.from_pretrained returned None — check HF_TOKEN and that "
            f"you've accepted the {DIARIZATION_MODEL} license on huggingface.co."
        )
    if DEVICE == "cuda":
        pipeline.to(torch.device("cuda"))

    diarization = pipeline(
        wav_path,
        min_speakers=MIN_SPEAKERS,
        max_speakers=MAX_SPEAKERS,
    )
    segs: list[dict] = []
    for turn, _, speaker in diarization.itertracks(yield_label=True):
        segs.append({
            "start": float(turn.start),
            "end": float(turn.end),
            "speaker": speaker,
        })
    segs.sort(key=lambda s: s["start"])
    del pipeline
    return segs


def _assign_speakers(words: list[dict], segs: list[dict]) -> list[dict]:
    """Pick the speaker whose diarization segment overlaps each word most."""
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
    if not HF_TOKEN:
        raise HTTPException(500, "HF_TOKEN not set — pyannote diarization requires it")

    suffix = os.path.splitext(file.filename or "audio.webm")[1] or ".webm"
    work_dir = tempfile.mkdtemp(prefix="diar-")
    upload_path = os.path.join(work_dir, "upload" + suffix)
    with open(upload_path, "wb") as f:
        f.write(await file.read())

    try:
        wav_path = _to_mono16k(upload_path, work_dir)

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

        speaker_segs = _diarize(wav_path)
        _free()

        words = _assign_speakers(words, speaker_segs)
        return {"text": _format(words)}
    finally:
        shutil.rmtree(work_dir, ignore_errors=True)
        _free()
