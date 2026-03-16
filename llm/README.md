# Local LLM (Ollama)

Runs [Ollama](https://ollama.com) in Docker with GPU-accelerated inference on the GTX 1070 Ti. [Open WebUI](https://github.com/open-webui/open-webui) provides a chat interface.

## Access

Local: `http://192.168.50.186:3000`
External: `https://llm.jasonfagerberg.duckdns.org`
API: `https://llm-api.jasonfagerberg.duckdns.org`

## Models

| Model | VRAM | Use |
|-------|------|-----|
| `qwen3:1.7b` | ~1.5GB | Fast, lightweight chat |
| `qwen3:8b` | ~5GB | General chat via Open WebUI |
| `qwen2.5-coder:7b` | ~5GB | Coding tasks via OpenCode |

Avoid 14B+ models — they exceed 8GB VRAM and will spill to CPU, making inference very slow.

Qwen3 supports built-in thinking mode. Append `/think` to a prompt to enable it, `/nothink` to disable.

## Chat via CLI

```bash
docker exec -it ollama ollama run qwen3:8b
```

## API

Ollama exposes an OpenAI-compatible REST API on port 11434:

```bash
curl http://192.168.50.186:11434/api/generate \
  -d '{"model": "qwen3:8b", "prompt": "Hello!", "stream": false}'
```

From outside your network — any tool that supports a custom OpenAI-compatible base URL:
```
Base URL: https://llm-api.jasonfagerberg.duckdns.org
API Key:  <your-key from NPM nginx config>
Model:    qwen2.5-coder:7b
```

> Auth is enforced by NPM's nginx config, not Ollama itself.

See [opencode_setup.md](opencode_setup.md) for OpenCode configuration.

## Managing Models

```bash
docker exec -it ollama ollama list
docker exec -it ollama ollama pull qwen3:8b
docker exec -it ollama ollama pull qwen2.5-coder:7b
```

## Resource Notes

- GPU inference on GTX 1070 Ti — expect ~15–30 tokens/sec on the 8B models
- Plex NVENC transcoding and LLM inference share the GPU but rarely overlap in practice
- Model files are stored in `./data`

## Updating

```bash
docker compose pull
docker compose up -d
```
