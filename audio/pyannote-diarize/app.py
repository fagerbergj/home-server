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
    # pyannote.audio 3.3.x takes `use_auth_token`. 3.4+ renamed it to `token`.
    # We're pinned to 3.3.2 in requirements.txt — verified via
    #   inspect.signature(Pipeline.from_pretrained)
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
    """Assign each word to a diarized speaker.

    First pass: pick the segment with the largest overlap. If there is no
    overlap (the word fell in a gap between diarization segments — pyannote
    occasionally leaves short silences unattributed), fall back to the
    speaker of the nearest segment by time distance. As a last resort
    (no segments at all), inherit the previous word's speaker.
    """
    if not segs:
        return [{**w, "speaker": "SPEAKER_??"} for w in words]

    out = []
    last_speaker = segs[0]["speaker"]
    for w in words:
        best_speaker, best_overlap = None, 0.0
        nearest_speaker, nearest_dist = None, float("inf")
        for s in segs:
            ov = max(0.0, min(w["end"], s["end"]) - max(w["start"], s["start"]))
            if ov > best_overlap:
                best_overlap = ov
                best_speaker = s["speaker"]
            # Distance from word's midpoint to segment's nearest edge.
            mid = (w["start"] + w["end"]) / 2
            if mid < s["start"]:
                dist = s["start"] - mid
            elif mid > s["end"]:
                dist = mid - s["end"]
            else:
                dist = 0.0
            if dist < nearest_dist:
                nearest_dist = dist
                nearest_speaker = s["speaker"]

        speaker = best_speaker or nearest_speaker or last_speaker
        last_speaker = speaker
        out.append({**w, "speaker": speaker})
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
        segments, info = whisper.transcribe(wav_path, word_timestamps=True)
        # The generator must be drained to materialize segments. Collecting
        # eagerly so we can log counts and fall back if word-level is empty.
        seg_list = list(segments)
        words: list[dict] = []
        for seg in seg_list:
            seg_words = list(seg.words or [])
            if seg_words:
                for w in seg_words:
                    words.append({
                        "start": float(w.start),
                        "end": float(w.end),
                        "word": w.word,
                    })
            elif (seg.text or "").strip():
                # word_timestamps yielded no words for this segment — fall back
                # to segment-level so we don't lose transcription.
                words.append({
                    "start": float(seg.start),
                    "end": float(seg.end),
                    "word": seg.text,
                })
        logger.info(
            "transcribed lang=%s duration=%.1fs segments=%d words=%d",
            getattr(info, "language", "?"),
            getattr(info, "duration", 0.0),
            len(seg_list),
            len(words),
        )
        del whisper
        _free()

        speaker_segs = _diarize(wav_path)
        _free()

        words = _assign_speakers(words, speaker_segs)
        return {"text": _format(words)}
    finally:
        shutil.rmtree(work_dir, ignore_errors=True)
        _free()
