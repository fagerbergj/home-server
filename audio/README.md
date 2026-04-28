# Audio

Speech-to-text + speaker diarization, fronted by an OpenAI-compatible HTTP API.

## What it is

A locally-built FastAPI service (`nemo-diarize/`) that runs:

- **[faster-whisper](https://github.com/SYSTRAN/faster-whisper)** for transcription — CTranslate2 backend, fast, GPU-accelerated.
- **[NVIDIA NeMo](https://github.com/NVIDIA/NeMo)** for speaker diarization — VAD → TitaNet speaker embeddings → clustering → MSDD.

Each request runs the full pipeline: transcribe → diarize → stitch → return `[SPEAKER_XX]`-labelled text. Models load and unload per request so VRAM is freed between calls (the GPU is shared with Ollama).

The container is named `faster-whisper` for compatibility with the existing `document-pipeline` client (`WHISPER_URL=http://faster-whisper:8000`).

## Prerequisites

- NVIDIA GPU + CUDA-capable host
- NVIDIA Container Toolkit
- ~10 GB free disk for the image, ~1 GB for cached models on first run

## Start

```bash
cd ~/workspace/home-server/audio
docker compose build faster-whisper      # ~10 min on first build (NeMo is heavy)
docker compose up -d faster-whisper
docker logs -f faster-whisper
```

First transcription request triggers NeMo model downloads (`titanet_large`, `vad_multilingual_marblenet`, `diar_msdd_telephonic` — ~500 MB total) into `./model-cache/`. After that it's offline.

## Configuration

Set in the root `.env`:

| Variable | Default | Notes |
|---|---|---|
| `WHISPER_MODEL` | `Systran/faster-whisper-large-v3` | HF model ID, used as the per-request default |
| `MAX_NUM_SPEAKERS` | `8` | Upper bound passed to NeMo's clustering — lower this if you only ever record 1-on-1s |
| `WHISPERX_BATCH_SIZE` | `16` | faster-whisper batch size; lower if you OOM during transcription |

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
| align (skipped — NeMo path uses faster-whisper word timestamps directly) | — | |
| diarize (VAD + TitaNet + MSDD) | ~2 GB | sequential within NeMo |

Cold-start ~10 s. If this is too slow for your use case, set the models to load eagerly at boot — the current behaviour is tuned for "shared GPU, occasional voice notes."

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

`nemo-diarize/` — FastAPI app (`app.py`), Dockerfile, requirements. ~250 lines total.
