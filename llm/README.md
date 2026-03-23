# Local LLM (Ollama)

Runs [Ollama](https://ollama.com) in Docker with GPU-accelerated inference on 2x GTX 1070 Ti. Ollama splits model layers across both GPUs (~16GB effective VRAM). [Open WebUI](https://github.com/open-webui/open-webui) provides a chat interface.

## Access

Local: `http://192.168.50.186:3000`
External: `https://llm.jasonfagerberg.duckdns.org`
API: `https://llm-api.jasonfagerberg.duckdns.org`

## Models

| Model | Tier | VRAM | Context Cap | Default For |
|-------|------|------|-------------|-------------|
| `qwen3-4b-32k` | Fast | ~2.5GB | 32K | Open WebUI (default) |
| `gpt-oss-20b-64k` | Middle | ~10.5GB | 64K | OpenCode |
| `devstral-24b-64k` | Smart | ~13.5GB | 64K | Complex coding tasks |

### Why context is capped

With ~16GB effective VRAM across both GPUs, model weights leave limited room for the KV cache (which grows with context length):

- **qwen3-4b-32k** — weights only ~2.5GB, 32K fits entirely in VRAM with room to spare. Also small enough to stay loaded in VRAM alongside whichever larger model was last used.
- **gpt-oss-20b-64k** — weights ~10.5GB, leaving ~5.5GB for KV cache. 64K context (~5.4GB KV) fits in VRAM with minimal spill to RAM (fine with 32GB).
- **devstral-24b-64k** — weights ~13.5GB, leaving only ~2.5GB for KV cache in VRAM. 64K context (~5.4GB KV) intentionally spills ~3GB into RAM (fine with 32GB system RAM). 128K would require ~21GB KV cache — too much.

All three are custom models created via Modelfile — see setup.md.

## Chat via CLI

```bash
docker exec -it ollama ollama run qwen3-4b-32k
```

## API

Ollama exposes an OpenAI-compatible REST API on port 11434:

```bash
curl http://192.168.50.186:11434/api/generate \
  -d '{"model": "qwen3-4b-32k", "prompt": "Hello!", "stream": false}'
```

From outside your network — any tool that supports a custom OpenAI-compatible base URL:
```
Base URL: https://llm-api.jasonfagerberg.duckdns.org
API Key:  <your-key from NPM nginx config>
Model:    gpt-oss-20b-64k  (or qwen3-4b-32k, devstral-24b-64k)
```

> Auth is enforced by NPM's nginx config, not Ollama itself.

## Managing Models

```bash
docker exec -it ollama ollama list
docker exec -it ollama ollama pull qwen3:4b
docker exec -it ollama ollama pull gpt-oss:20b
docker exec -it ollama ollama pull devstral
```

## Resource Notes

- GPU inference across 2x GTX 1070 Ti (~16GB effective VRAM) — expect ~15–30 tokens/sec on small models, slower on 20B+
- `qwen3-4b-32k` stays loaded in VRAM alongside larger models due to its small footprint — fast responses with no load delay
- Plex NVENC transcoding and LLM inference share the GPU but rarely overlap in practice
- Model files are stored in `./data`

## Updating

```bash
docker compose pull
docker compose up -d
```
