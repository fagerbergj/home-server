"""FastAPI wrapper: whisper.cpp transcription + pyannote speaker diarization.

Endpoint matches the OpenAI /v1/audio/transcriptions shape that the existing
document-pipeline Go client already speaks. Returns:
    {"text": "[SPEAKER_00] hello there\\n\\n[SPEAKER_01] hi"}

Transcription shells out to whisper-cli built with GGML_HIP=ON so it runs on
the R9700. Pyannote runs in a per-request subprocess (gpu_worker.py) so that
the HIP context — and its persistent KFD event-wait thread that busy-polls
one CPU core indefinitely — dies after each request instead of accumulating
in the long-lived FastAPI process.
"""
from __future__ import annotations

import json
import logging
import os
import shutil
import subprocess
import sys
import tempfile

import torch
from fastapi import FastAPI, Form, HTTPException, UploadFile

# Fail loudly at startup if torch isn't the ROCm build — pip resolving
# pyannote.audio's deps can silently replace the base image's ROCm-built
# torch wheel with a CUDA-only wheel from PyPI, which presents as "no NVIDIA
# driver" at the first .to("cuda") call. The Dockerfile uses a pip
# constraints file to prevent this; this check catches future regressions.
# `torch.version.hip` is a compile-time attribute — reading it does NOT
# initialize the HIP runtime, so the parent process stays GPU-clean.
if torch.version.hip is None:
    raise RuntimeError(
        f"torch {torch.__version__} is not a ROCm build "
        f"(torch.version.hip is None, torch.version.cuda={torch.version.cuda}). "
        "pip likely replaced the base image's ROCm torch — check Dockerfile "
        "constraints."
    )

WHISPER_MODEL_PATH = os.environ.get("WHISPER_MODEL_PATH", "/models/ggml-large-v3.bin")
VAD_MODEL_PATH = os.environ.get("VAD_MODEL_PATH", "/models/ggml-silero-v5.1.2.bin")
DIARIZATION_MODEL = os.environ.get(
    "DIARIZATION_MODEL", "pyannote/speaker-diarization-3.1"
)
EMBEDDING_MODEL = os.environ.get("EMBEDDING_MODEL", "pyannote/embedding")
HF_TOKEN = os.environ.get("HF_TOKEN")
MIN_SPEAKERS = int(os.environ.get("MIN_SPEAKERS", "1"))
MAX_SPEAKERS = int(os.environ.get("MAX_SPEAKERS", "8"))
SPEAKER_MATCH_THRESHOLD = float(os.environ.get("SPEAKER_MATCH_THRESHOLD", "0.5"))
VOICEPRINTS_PATH = os.environ.get("VOICEPRINTS_PATH", "/root/.cache/voiceprints.json")
MIN_ENROLL_SEG_SEC = float(os.environ.get("MIN_ENROLL_SEG_SEC", "1.0"))
# Hard cap on a single transcription's GPU phase. Diarizing a 1-hour wav on
# the R9700 is well under 2 minutes; anything past 10 min is a hung worker.
WORKER_TIMEOUT_SEC = float(os.environ.get("WORKER_TIMEOUT_SEC", "600"))

WORKER_SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gpu_worker.py")

app = FastAPI()
logger = logging.getLogger("uvicorn.error")


def _load_voiceprints() -> dict[str, list[list[float]]]:
    if not os.path.exists(VOICEPRINTS_PATH):
        return {}
    try:
        with open(VOICEPRINTS_PATH) as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        logger.warning("voiceprints.json corrupt or unreadable; starting fresh")
        return {}


def _save_voiceprints(prints: dict) -> None:
    os.makedirs(os.path.dirname(VOICEPRINTS_PATH), exist_ok=True)
    tmp = VOICEPRINTS_PATH + ".tmp"
    with open(tmp, "w") as f:
        json.dump(prints, f)
    os.replace(tmp, VOICEPRINTS_PATH)


def _run_worker(cmd: str, task: dict):
    """Run gpu_worker.py in a subprocess. JSON in via stdin, JSON out via
    stdout, log lines via stderr. The subprocess exits when done, taking
    its HIP context (and the busy-polling KFD event-wait thread) with it."""
    payload = json.dumps(task)
    try:
        proc = subprocess.run(
            [sys.executable, WORKER_SCRIPT, cmd],
            input=payload,
            capture_output=True,
            text=True,
            timeout=WORKER_TIMEOUT_SEC,
            check=False,
        )
    except subprocess.TimeoutExpired as e:
        raise RuntimeError(f"gpu_worker {cmd} timed out after {WORKER_TIMEOUT_SEC}s") from e
    if proc.stderr:
        for line in proc.stderr.rstrip().splitlines():
            logger.info("worker[%s]: %s", cmd, line)
    if proc.returncode != 0:
        raise RuntimeError(
            f"gpu_worker {cmd} exited {proc.returncode}: {proc.stderr[-2000:]}"
        )
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError as e:
        raise RuntimeError(
            f"gpu_worker {cmd} stdout was not JSON: {proc.stdout[:500]!r}"
        ) from e


def _transcribe(wav_path: str, work_dir: str) -> list[dict]:
    """Run whisper-cli on the wav file. Returns list of {start, end, word}.

    -ml 1 forces one-word-per-segment so we get word-level timestamps in the
    JSON output (matches what faster-whisper's word_timestamps=True gave us).
    --vad + Silero model preserves the trailing-edge hallucination suppression
    that vad_filter did previously.
    """
    out_prefix = os.path.join(work_dir, "whisper")
    cmd = [
        "whisper-cli",
        "-m", WHISPER_MODEL_PATH,
        "-f", wav_path,
        "-oj",                    # output JSON
        "-of", out_prefix,
        "-ml", "1",               # one-word-per-segment
        "-nt",                    # no inline timestamps in text
        "-l", "auto",
        "--no-prints",            # suppress progress chatter on stdout
    ]
    if os.path.exists(VAD_MODEL_PATH):
        cmd.extend(["--vad", "--vad-model", VAD_MODEL_PATH])
    else:
        logger.warning("VAD model not at %s — transcribing without VAD",
                       VAD_MODEL_PATH)

    try:
        subprocess.run(cmd, check=True, capture_output=True)
    except subprocess.CalledProcessError as e:
        raise RuntimeError(
            f"whisper-cli failed (exit {e.returncode}): {e.stderr.decode()[:2000]}"
        ) from e

    json_path = out_prefix + ".json"
    with open(json_path) as f:
        data = json.load(f)

    words: list[dict] = []
    for seg in data.get("transcription", []):
        text = (seg.get("text") or "").strip()
        if not text:
            continue
        offsets = seg.get("offsets", {})
        words.append({
            "start": float(offsets.get("from", 0)) / 1000.0,  # ms → s
            "end": float(offsets.get("to", 0)) / 1000.0,
            # Preserve leading space so the formatter joins words without
            # gluing them together.
            "word": text if text.startswith(" ") else " " + text,
        })
    return words


def _to_mono16k(src: str, dst_dir: str) -> str:
    """pyannote prefers 16 kHz mono wav; ffmpeg-convert."""
    dst = os.path.join(dst_dir, "audio.16k.wav")
    subprocess.run(
        ["ffmpeg", "-y", "-i", src, "-ar", "16000", "-ac", "1", dst],
        check=True, capture_output=True,
    )
    return dst


def _diarize(wav_path: str) -> list[dict]:
    """Diarize + voiceprint-relabel in a subprocess. Returns list of
    {start, end, speaker} sorted by start."""
    return _run_worker("diarize", {
        "wav_path": wav_path,
        "diarization_model": DIARIZATION_MODEL,
        "embedding_model": EMBEDDING_MODEL,
        "min_speakers": MIN_SPEAKERS,
        "max_speakers": MAX_SPEAKERS,
        "voiceprints": _load_voiceprints(),
        "min_enroll_seg_sec": MIN_ENROLL_SEG_SEC,
        "speaker_match_threshold": SPEAKER_MATCH_THRESHOLD,
    })


def _embed_audio(wav_path: str) -> list[float]:
    """Compute a speaker embedding for the whole file in a subprocess."""
    return _run_worker("embed", {
        "wav_path": wav_path,
        "embedding_model": EMBEDDING_MODEL,
    })


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


@app.get("/v1/speakers")
def list_speakers():
    """List enrolled speaker names and how many samples each has."""
    voiceprints = _load_voiceprints()
    return {name: len(embs) for name, embs in voiceprints.items()}


@app.delete("/v1/speakers/{name}")
def delete_speaker(name: str):
    voiceprints = _load_voiceprints()
    if name not in voiceprints:
        raise HTTPException(404, f"no speaker named {name!r}")
    del voiceprints[name]
    _save_voiceprints(voiceprints)
    return {"deleted": name}


@app.post("/v1/speakers/enroll")
async def enroll_speaker(file: UploadFile, name: str = Form(...)):
    """Enroll a voice sample for `name`. Multiple samples per name accumulate
    and are all matched against during transcription. 10-30 seconds of clean
    single-speaker audio is the sweet spot."""
    if not HF_TOKEN:
        raise HTTPException(500, "HF_TOKEN not set — pyannote embedding requires it")
    name = (name or "").strip()
    if not name:
        raise HTTPException(400, "name is required")

    suffix = os.path.splitext(file.filename or "audio.wav")[1] or ".wav"
    work_dir = tempfile.mkdtemp(prefix="enroll-")
    upload_path = os.path.join(work_dir, "upload" + suffix)
    with open(upload_path, "wb") as f:
        f.write(await file.read())

    try:
        wav_path = _to_mono16k(upload_path, work_dir)
        emb = _embed_audio(wav_path)
        voiceprints = _load_voiceprints()
        voiceprints.setdefault(name, []).append(emb)
        _save_voiceprints(voiceprints)
        logger.info("enrolled %s — now %d sample(s)", name, len(voiceprints[name]))
        return {"name": name, "sample_count": len(voiceprints[name])}
    finally:
        shutil.rmtree(work_dir, ignore_errors=True)


@app.post("/v1/audio/transcriptions")
async def transcribe(file: UploadFile, model: str = Form("")):
    """Transcribe + diarize. `model` form field is accepted for API
    compatibility with the OpenAI shape but ignored — the model is fixed
    at container start via WHISPER_MODEL_PATH. To switch models, mount a
    different .bin and change the env var."""
    if not HF_TOKEN:
        raise HTTPException(500, "HF_TOKEN not set — pyannote diarization requires it")

    suffix = os.path.splitext(file.filename or "audio.webm")[1] or ".webm"
    work_dir = tempfile.mkdtemp(prefix="diar-")
    upload_path = os.path.join(work_dir, "upload" + suffix)
    with open(upload_path, "wb") as f:
        f.write(await file.read())

    try:
        wav_path = _to_mono16k(upload_path, work_dir)

        logger.info("transcribing model=%s", WHISPER_MODEL_PATH)
        words = _transcribe(wav_path, work_dir)
        logger.info("transcribed words=%d", len(words))

        speaker_segs = _diarize(wav_path)

        words = _assign_speakers(words, speaker_segs)
        return {"text": _format(words)}
    finally:
        shutil.rmtree(work_dir, ignore_errors=True)
