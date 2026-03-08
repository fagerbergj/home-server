# Local LLM (Ollama + DeepSeek)

Runs [Ollama](https://ollama.com) in Docker, which handles model downloads, quantization, and serves a local API. Uses the GTX 1070 Ti for GPU-accelerated inference via the NVIDIA Container Toolkit set up in Phase 4.

## Start

```bash
docker compose up -d
```

## Pull a Model

Once the container is running, pull a DeepSeek model:

```bash
docker exec -it ollama ollama pull deepseek-r1:7b
```

### Recommended models for 8GB VRAM

| Model | VRAM | Notes |
|-------|------|-------|
| `deepseek-r1:1.5b` | ~1.5GB | Fast, lightweight |
| `deepseek-r1:7b` | ~4.5GB | Best balance of speed and quality |
| `deepseek-r1:8b` | ~5.5GB | Slightly better, still fits comfortably |

Avoid 14B+ models — they exceed 8GB VRAM and will spill to CPU, making inference very slow.

## Chat via CLI

```bash
docker exec -it ollama ollama run deepseek-r1:7b
```

## API

Ollama exposes a REST API on port 11434:

```bash
curl http://<server-ip>:11434/api/generate \
  -d '{"model": "deepseek-r1:7b", "prompt": "Hello!", "stream": false}'
```

## List Downloaded Models

```bash
docker exec -it ollama ollama list
```

## Resource Notes

- GPU inference runs on the GTX 1070 Ti — expect ~15–30 tokens/sec on a 7B model
- Plex NVENC transcoding and LLM inference share the GPU but rarely overlap in practice
- Model files are stored in `./data` — the 7B model is ~4.5GB on disk

## External Access

Open WebUI is accessible from your local network at `http://<server-ip>:3000`.

For access outside your home network, Nginx Proxy Manager handles it — see [`networking/README.md`](../networking/README.md). Once configured, you can reach it at `https://llm.yourname.asuscomm.com` from any browser or device.

Port 11434 (Ollama API) is local-only by default. Point CLI clients at the server IP on your home network:
```bash
OLLAMA_HOST=http://<server-ip>:11434 ollama run deepseek-r1:7b
```

## Updating

```bash
docker compose pull
docker compose up -d
```
