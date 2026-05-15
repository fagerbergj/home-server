# Audio

Speech-to-text + speaker diarization, fronted by an OpenAI-compatible HTTP API.

## What it is

A locally-built FastAPI service (`pyannote-diarize/`) that runs:

- **[whisper.cpp](https://github.com/ggml-org/whisper.cpp)** for transcription — built with HIPBLAS (`GGML_HIP=ON`, `AMDGPU_TARGETS=gfx1201`) so it runs on the R9700 via ROCm.
- **[pyannote.audio](https://github.com/pyannote/pyannote-audio)** for speaker diarization — chosen over alternatives for hours-long multi-speaker audio (DnD sessions, podcasts, meetings).

Each request runs: transcribe → diarize → stitch → return `[SPEAKER_XX]`-labelled text. Models load and unload per request so VRAM is freed between calls (the GPU is shared with Ollama).

The container is named `faster-whisper` for compatibility with the existing `document-pipeline` client (`WHISPER_URL=http://faster-whisper:8000`).

## Prerequisites

- AMD GPU with ROCm (`/dev/kfd` + `/dev/dri` accessible, user in `render` and `video` groups)
- ggml model files on the host at `/mnt/cache/whisper-models/` — see [setup.md](setup.md)
- A Hugging Face token with the pyannote licenses accepted — see [setup.md](setup.md)

## Start

```bash
cd ~/workspace/home-server/audio
docker compose build faster-whisper
docker compose up -d faster-whisper
docker logs -f faster-whisper
```

First transcription request downloads pyannote models (~500 MB) into `./model-cache/`. After that it's offline.

## Configuration

Set in the root `.env` or `docker-compose.yml` environment:

| Variable | Default | Notes |
|---|---|---|
| `HF_TOKEN` | _(required)_ | Hugging Face read token; see above |
| `WHISPER_MODEL_PATH` | `/models/ggml-large-v3.bin` | Path inside container to the ggml model file |
| `VAD_MODEL_PATH` | `/models/ggml-silero-v5.1.2.bin` | Silero VAD model — suppresses hallucination tails |
| `DIARIZATION_MODEL` | `pyannote/speaker-diarization-3.1` | pyannote pipeline ID |
| `MIN_SPEAKERS` | `1` | Lower bound for clustering |
| `MAX_SPEAKERS` | `8` | Upper bound — set to your typical group size |

Model files are mounted read-only from `/mnt/cache/whisper-models/` on the host. Download them once:

```bash
# ggml-large-v3 (~1.5 GB)
wget -P /mnt/cache/whisper-models \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin

# Silero VAD (~10 MB)
wget -P /mnt/cache/whisper-models \
  https://huggingface.co/snakers4/silero-vad/resolve/master/files/silero_vad.onnx
```

> **Note:** whisper-cli expects the Silero model as a `.bin` file. Rename it to `ggml-silero-v5.1.2.bin` after downloading, or update `VAD_MODEL_PATH` to match whatever filename you use.

## API

OpenAI-compatible. Exposed on host port `8005`, container port `8000`.

```bash
curl http://localhost:8005/v1/audio/transcriptions \
  -F "file=@recording.webm" \
  -F "model=ignored"
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
| transcribe (whisper.cpp large-v3) | ~2–3 GB | whisper-cli subprocess, HIPBLAS |
| diarize (pyannote 3.1) | ~2 GB | segmentation + embedding + clustering, sequential |

Cold-start ~5–10 s. Throughput on the R9700 is similar to or faster than the 3090 for transcription; diarization throughput TBD (roughly **10% of audio length** on the 3090 as a baseline).

## Updates

Watchtower **does not** update this container — it's a locally built image. To rebuild after pulling code changes:

```bash
cd ~/workspace/home-server/audio
git pull
docker compose build faster-whisper
docker compose up -d faster-whisper
```

## Integration

The `document-pipeline` service joins the same docker network and reaches this at `http://faster-whisper:8000`. Wired via the `audio_default` external network — see `~/workspace/document-pipeline/docker-compose.yml`.

## Source

`pyannote-diarize/` — FastAPI app (`app.py`), Dockerfile, requirements. Multi-stage build: stage 1 compiles whisper.cpp with HIPBLAS, stage 2 is the runtime with pyannote installed on the ROCm PyTorch base.
