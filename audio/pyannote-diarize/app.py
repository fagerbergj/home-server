"""FastAPI wrapper: whisper.cpp transcription + pyannote speaker diarization.

Endpoint matches the OpenAI /v1/audio/transcriptions shape that the existing
document-pipeline Go client already speaks. Returns:
    {"text": "[SPEAKER_00] hello there\\n\\n[SPEAKER_01] hi"}

Transcription shells out to whisper-cli built with GGML_HIP=ON so it runs on
the R9700. Pyannote runs in-process via the ROCm-built torch from the base
image. Models load per request and free between calls — the GPU is shared
with Ollama in this setup.
"""
from __future__ import annotations

import gc
import json
import logging
import os
import shutil
import subprocess
import tempfile

import numpy as np
import torch
import torchaudio
from fastapi import FastAPI, Form, HTTPException, UploadFile

# torchaudio 2.5+ removed AudioMetaData from the top-level namespace but
# pyannote.audio 3.3.x uses it as a return-type annotation in io.py, which
# is evaluated at import time. Restore it so pyannote can be imported.
if not hasattr(torchaudio, "AudioMetaData"):
    from typing import NamedTuple

    class _AudioMetaData(NamedTuple):
        sample_rate: int
        num_frames: int
        num_channels: int
        bits_per_sample: int
        encoding: str

    torchaudio.AudioMetaData = _AudioMetaData  # type: ignore[attr-defined]

# torchaudio 2.5+ removed list_audio_backends(); pyannote 3.3.x calls it in
# Audio.__init__ to select the I/O backend. Return soundfile which is always
# available as a pyannote dependency.
if not hasattr(torchaudio, "list_audio_backends"):
    torchaudio.list_audio_backends = lambda: ["soundfile"]  # type: ignore[attr-defined]

# PyTorch 2.6+ changed torch.load default to weights_only=True. pyannote
# checkpoints embed many custom classes (TorchVersion, Specifications, …)
# that aren't in the default allowlist.
#
# Patch lightning_fabric.utilities.cloud_io._load — the exact function that
# pyannote imports as `pl_load` — to pass weights_only=False explicitly.
# Patching here before pyannote is ever imported means pyannote's module-level
# `from lightning_fabric.utilities.cloud_io import _load as pl_load` picks up
# our patched version. Safe: all checkpoints come from the HuggingFace hub.
import lightning_fabric.utilities.cloud_io as _lf_cloud_io

_orig_lf_load = _lf_cloud_io._load

def _lf_load_weights_any(path_or_url, map_location=None, **kwargs):
    # Ignore any weights_only kwarg from callers (pytorch_lightning passes it
    # explicitly); always use False since checkpoints come from HF hub.
    return torch.load(path_or_url, map_location=map_location, weights_only=False)

_lf_cloud_io._load = _lf_load_weights_any

# DEVICE stays "cuda" for pyannote — ROCm-built PyTorch presents the CUDA API,
# so `torch.device("cuda")` resolves to the R9700 transparently.
DEVICE = os.environ.get("DEVICE", "cuda")
# Path to a whisper.cpp ggml model file inside the container. The default
# matches the volume layout in docker-compose.yml (host /mnt/cache/whisper-models).
WHISPER_MODEL_PATH = os.environ.get("WHISPER_MODEL_PATH", "/models/ggml-large-v3.bin")
# Silero VAD model for whisper.cpp's --vad flag. Same trailing-edge
# hallucination suppression that vad_filter gave us under faster-whisper.
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

app = FastAPI()
logger = logging.getLogger("uvicorn.error")


def _free():
    gc.collect()
    if DEVICE == "cuda":
        torch.cuda.empty_cache()


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


def _cosine(a, b) -> float:
    av = np.asarray(a, dtype=np.float32).flatten()
    bv = np.asarray(b, dtype=np.float32).flatten()
    denom = float(np.linalg.norm(av) * np.linalg.norm(bv)) + 1e-10
    return float(np.dot(av, bv) / denom)


def _embed_audio(wav_path: str, start: float | None = None, end: float | None = None) -> list[float]:
    """Compute a speaker embedding for the whole file or a [start, end] segment."""
    from pyannote.audio import Inference
    from pyannote.core import Segment

    inference = Inference(
        EMBEDDING_MODEL,
        window="whole",
        use_auth_token=HF_TOKEN,
        device=torch.device(DEVICE) if DEVICE == "cuda" else torch.device("cpu"),
    )
    if start is None:
        emb = inference(wav_path)
    else:
        emb = inference.crop(wav_path, Segment(start, end))
    del inference
    return np.asarray(emb).flatten().tolist()


def _match_voiceprint(embedding, voiceprints: dict) -> tuple[str, float] | None:
    """Find the enrolled name with highest cosine similarity, if it crosses
    SPEAKER_MATCH_THRESHOLD."""
    best_name, best_sim = None, 0.0
    for name, embs in voiceprints.items():
        for e in embs:
            sim = _cosine(embedding, e)
            if sim > best_sim:
                best_sim = sim
                best_name = name
    if best_name and best_sim >= SPEAKER_MATCH_THRESHOLD:
        return best_name, best_sim
    return None


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
    _free()

    # Voiceprint relabeling: if any speakers are enrolled, compute an embedding
    # for each pyannote SPEAKER_XX (using their longest segment) and replace the
    # label with the closest enrolled name when similarity crosses the threshold.
    voiceprints = _load_voiceprints()
    if not voiceprints or not segs:
        return segs

    by_speaker: dict[str, list[dict]] = {}
    for s in segs:
        by_speaker.setdefault(s["speaker"], []).append(s)

    relabel: dict[str, str] = {}
    for speaker, sps in by_speaker.items():
        longest = max(sps, key=lambda s: s["end"] - s["start"])
        dur = longest["end"] - longest["start"]
        if dur < MIN_ENROLL_SEG_SEC:
            logger.info("voiceprint: skip %s, longest segment %.2fs < %.2fs",
                        speaker, dur, MIN_ENROLL_SEG_SEC)
            continue
        try:
            emb = _embed_audio(wav_path, longest["start"], longest["end"])
        except Exception as e:
            logger.warning("voiceprint: embedding failed for %s: %s", speaker, e)
            continue
        match = _match_voiceprint(emb, voiceprints)
        if match:
            name, sim = match
            logger.info("voiceprint: %s -> %s (sim=%.3f)", speaker, name, sim)
            relabel[speaker] = name
        else:
            logger.info("voiceprint: no match for %s above threshold %.2f",
                        speaker, SPEAKER_MATCH_THRESHOLD)
    _free()

    if relabel:
        for s in segs:
            if s["speaker"] in relabel:
                s["speaker"] = relabel[s["speaker"]]

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
        _free()


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
        _free()

        speaker_segs = _diarize(wav_path)
        _free()

        words = _assign_speakers(words, speaker_segs)
        return {"text": _format(words)}
    finally:
        shutil.rmtree(work_dir, ignore_errors=True)
        _free()
