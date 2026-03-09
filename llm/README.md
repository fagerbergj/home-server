# Local LLM (Ollama + Qwen3)

Runs [Ollama](https://ollama.com) in Docker, which handles model downloads, quantization, and serves a local API. Uses the RTX 4070 for GPU-accelerated inference via the NVIDIA Container Toolkit set up in Phase 4.

## Start

```bash
docker compose up -d
```

## Pull a Model

Once the container is running, pull Qwen3 14B:

```bash
docker exec -it ollama ollama pull qwen3:14b
```

### Recommended models for 12GB VRAM

| Model | VRAM | Notes |
|-------|------|-------|
| `qwen3:8b` | ~5GB | Fast, still capable |
| `qwen3:14b` | ~9GB | Best fit for 12GB VRAM — recommended |
| `qwen3:32b` | ~20GB | Exceeds VRAM, avoid |

Qwen3 supports a built-in thinking mode for step-by-step reasoning. Enable it by appending `/think` to your prompt, or disable it with `/no_think`.

## Chat via CLI

```bash
docker exec -it ollama ollama run qwen3:14b
```

## API

Ollama exposes a REST API on port 11434:

```bash
curl http://<server-ip>:11434/api/generate \
  -d '{"model": "qwen3:14b", "prompt": "Hello!", "stream": false}'
```

## List Downloaded Models

```bash
docker exec -it ollama ollama list
```

## Resource Notes

- GPU inference runs on the RTX 4070 — expect ~30–50 tokens/sec on the 14B model
- Plex NVENC transcoding and LLM inference share the GPU but rarely overlap in practice
- Model files are stored in `./data` — the 14B model is ~9GB on disk

## External Access

Open WebUI is accessible from your local network at `http://<server-ip>:3000`.

For access outside your home network, Nginx Proxy Manager handles it — see [`networking/README.md`](../networking/README.md). Once configured, you can reach it at `https://llm.yourname.asuscomm.com` from any browser or device.

Port 11434 (Ollama API) is local-only by default. Point CLI clients at the server IP on your home network:
```bash
OLLAMA_HOST=http://<server-ip>:11434 ollama run qwen3:14b
```

## Updating

```bash
docker compose pull
docker compose up -d
```
