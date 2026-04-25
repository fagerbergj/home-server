# Audio Setup

GPU-accelerated speech-to-text via [faster-whisper-server](https://github.com/fedirz/faster-whisper-server).

## Prerequisites

- NVIDIA GPU with CUDA support (Phase 3 complete)
- NVIDIA Container Toolkit installed (Phase 5 complete)

## Start

```bash
cd ~/workspace/home-server/audio
docker compose up -d
```

On first start the container downloads the model (~3GB for large-v3). Check progress:

```bash
docker logs -f faster-whisper
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `WHISPER_MODEL` | `Systran/faster-whisper-large-v3` | HuggingFace model ID |

Set `WHISPER_MODEL` in your root `.env` to override. Smaller/faster alternatives:
- `Systran/faster-whisper-medium` — good accuracy, lower VRAM
- `Systran/faster-whisper-base` — fast, lower accuracy

## API

Exposes an OpenAI-compatible transcription endpoint on port 8005:

```bash
curl http://192.168.50.186:8005/v1/audio/transcriptions \
  -F "file=@recording.webm" \
  -F "model=Systran/faster-whisper-large-v3"
```

## Integration

The document pipeline (audio-bridge) will call this service at `http://faster-whisper:8000` internally. Wire it into the `api_gateway` network when ready:

```yaml
networks:
  api_gateway:
    external: true
    name: api_gateway
```
