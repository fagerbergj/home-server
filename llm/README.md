# Local LLM (Ollama + Qwen3)

Runs [Ollama](https://ollama.com) in Docker with GPU-accelerated inference on the GTX 1070 Ti. [Open WebUI](https://github.com/open-webui/open-webui) provides a chat interface.

## Access

Local: `http://<server-ip>:3000`
External: `https://llm.jasonfagerberg.asuscomm.com`
API: `https://llm-api.jasonfagerberg.asuscomm.com`

## Models

| Model | VRAM | Notes |
|-------|------|-------|
| `qwen3:1.7b` | ~1.5GB | Fast, lightweight |
| `qwen3:8b` | ~5GB | Best balance of speed and quality — recommended |

Avoid 14B+ models — they exceed 8GB VRAM and will spill to CPU, making inference very slow.

Qwen3 supports built-in thinking mode. Append `/think` to a prompt to enable it, `/no_think` to disable.

## Chat via CLI

```bash
docker exec -it ollama ollama run qwen3:8b
```

## API

Ollama exposes an OpenAI-compatible REST API on port 11434:

```bash
curl http://<server-ip>:11434/api/generate \
  -d '{"model": "qwen3:8b", "prompt": "Hello!", "stream": false}'
```

From outside your network — any tool that supports a custom OpenAI-compatible base URL:
```
Base URL: https://llm-api.jasonfagerberg.asuscomm.com
API Key:  <your-key from .env>
Model:    qwen3:8b
```

## Managing Models

```bash
docker exec -it ollama ollama list
docker exec -it ollama ollama pull qwen3:8b
```

## Resource Notes

- GPU inference on GTX 1070 Ti — expect ~15–30 tokens/sec on the 8B model
- Plex NVENC transcoding and LLM inference share the GPU but rarely overlap in practice
- Model files are stored in `./data` — the 8B model is ~5GB on disk

## Updating

```bash
docker compose pull
docker compose up -d
```
