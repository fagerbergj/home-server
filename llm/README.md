# Local LLM (Ollama)

Runs [Ollama](https://ollama.com) in Docker with GPU-accelerated inference on 2x GTX 1070 Ti. Ollama splits model layers across both GPUs (~16GB effective VRAM). [Open WebUI](https://github.com/open-webui/open-webui) provides a chat interface.

## Access

Local: `http://192.168.50.186:3000`
External: `https://llm.jasonfagerberg.duckdns.org`
API: `https://llm-api.jasonfagerberg.duckdns.org`

## Models

| Model | VRAM | Use |
|-------|------|-----|
| `qwen2.5-coder:7b` | ~5GB | Small coding tasks |
| `llama3.1:8b` | ~5GB | Chat |
| `mistral-nemo:12b` | ~7GB | Large coding tasks |

With ~16GB effective VRAM across both GPUs, models up to ~13B run fully on GPU. Larger models (30B+) will start spilling to CPU.

## Chat via CLI

```bash
docker exec -it ollama ollama run llama3.1:8b
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
Model:    llama3.1:8b  (or qwen2.5-coder:7b, mistral-nemo:12b)
```

> Auth is enforced by NPM's nginx config, not Ollama itself.

See [npcsh_setup.md](npcsh_setup.md) for npcsh configuration.

## Managing Models

```bash
docker exec -it ollama ollama list
docker exec -it ollama ollama pull qwen2.5-coder:7b
docker exec -it ollama ollama pull llama3.1:8b
docker exec -it ollama ollama pull mistral-nemo:12b
```

## Resource Notes

- GPU inference across 2x GTX 1070 Ti (~16GB effective VRAM) — expect ~15–30 tokens/sec on 7–8B models, slower on 12B+
- Plex NVENC transcoding and LLM inference share the GPU but rarely overlap in practice
- Model files are stored in `./data`

## Updating

```bash
docker compose pull
docker compose up -d
```
