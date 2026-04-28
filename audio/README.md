# Audio

Speech-to-text + speaker diarization, fronted by an OpenAI-compatible HTTP API.

## What it is

A locally-built FastAPI service (`pyannote-diarize/`) that runs:

- **[faster-whisper](https://github.com/SYSTRAN/faster-whisper)** for transcription — CTranslate2 backend, fast, GPU-accelerated.
- **[pyannote.audio](https://github.com/pyannote/pyannote-audio)** for speaker diarization — chosen over alternatives for hours-long multi-speaker audio (DnD sessions, podcasts, meetings).

Each request runs: transcribe → diarize → stitch → return `[SPEAKER_XX]`-labelled text. Models load and unload per request so VRAM is freed between calls (the GPU is shared with Ollama).

The container is named `faster-whisper` for compatibility with the existing `document-pipeline` client (`WHISPER_URL=http://faster-whisper:8000`).

## Prerequisites

- NVIDIA GPU with driver supporting CUDA 12.1+ (565+ recommended)
- NVIDIA Container Toolkit
- A Hugging Face token with the pyannote licenses accepted — see [setup.md](setup.md)
- ~5 GB free disk for the image, ~500 MB for cached models on first run

## Start

```bash
cd ~/workspace/home-server/audio
docker compose build faster-whisper
docker compose up -d faster-whisper
docker logs -f faster-whisper
```

First transcription request downloads pyannote models (~500 MB) into `./model-cache/`. After that it's offline.

## Configuration

Set in the root `.env`:

| Variable | Default | Notes |
|---|---|---|
| `HF_TOKEN` | _(required)_ | Hugging Face read token; see above |
| `WHISPER_MODEL` | `Systran/faster-whisper-large-v3` | HF model ID for transcription |
| `DIARIZATION_MODEL` | `pyannote/speaker-diarization-3.1` | pyannote pipeline ID |
| `MIN_SPEAKERS` | `1` | Lower bound for clustering |
| `MAX_SPEAKERS` | `8` | Upper bound — set to your typical group size |

faster-whisper model alternatives if VRAM is tight:
- `Systran/faster-whisper-medium` — solid accuracy, ~half the VRAM
- `Systran/faster-whisper-base` — fast, noticeably lower accuracy

## API

OpenAI-compatible. Exposed on host port `8005`, container port `8000`.

```bash
curl http://localhost:8005/v1/audio/transcriptions \
  -F "file=@recording.webm" \
  -F "model=Systran/faster-whisper-large-v3"
```

Response:

```json
{
  "text": "[SPEAKER_00] hey did you see the email\n\n[SPEAKER_01] yeah I'm on it"
}
```

Health check: `GET /health` → `{"status": "ok"}`.

## VRAM behaviour

Per-request cycle (released between requests):

| Step | VRAM | Notes |
|---|---|---|
| transcribe (large-v3) | ~3 GB | faster-whisper, CTranslate2 |
| diarize (pyannote 3.1) | ~2 GB | segmentation + embedding + clustering, sequential |

Cold-start ~5–10 s. Throughput on a 3090: roughly **10% of audio length** for diarization (a 4-hour session takes ~25 min to process).

## Updates

Watchtower **does not** update this container — it's a locally built image. To rebuild after pulling code changes:

```bash
cd ~/workspace/home-server/audio
docker compose build faster-whisper
docker compose up -d faster-whisper
```

## Integration

The `document-pipeline` service joins the same docker network and reaches this at `http://faster-whisper:8000`. Wired via the `audio_default` external network — see `~/workspace/document-pipeline/docker-compose.yml`.

## Source

`pyannote-diarize/` — FastAPI app (`app.py`), Dockerfile, requirements. ~150 lines total.
