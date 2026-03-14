# Local LLM (Ollama + Qwen3)

Runs [Ollama](https://ollama.com) in Docker, which handles model downloads, quantization, and serves a local API. Uses the GTX 1070 Ti for GPU-accelerated inference via the NVIDIA Container Toolkit set up in Phase 4.

## Start

```bash
docker compose up -d
```

## Pull a Model

Once the container is running, pull Qwen3 8B:

```bash
docker exec -it ollama ollama pull qwen3:8b
```

### Recommended models for 8GB VRAM

| Model | VRAM | Notes |
|-------|------|-------|
| `qwen3:1.7b` | ~1.5GB | Fast, lightweight |
| `qwen3:8b` | ~5GB | Best balance of speed and quality — recommended |

Avoid 14B+ models — they exceed 8GB VRAM and will spill to CPU, making inference very slow.

Qwen3 supports a built-in thinking mode for step-by-step reasoning. Enable it by appending `/think` to your prompt, or disable it with `/no_think`.

## Chat via CLI

```bash
docker exec -it ollama ollama run qwen3:8b
```

## API

Ollama exposes a REST API on port 11434:

```bash
curl http://<server-ip>:11434/api/generate \
  -d '{"model": "qwen3:8b", "prompt": "Hello!", "stream": false}'
```

## List Downloaded Models

```bash
docker exec -it ollama ollama list
```

## Resource Notes

- GPU inference runs on the GTX 1070 Ti — expect ~15–30 tokens/sec on the 8B model
- Plex NVENC transcoding and LLM inference share the GPU but rarely overlap in practice
- Model files are stored in `./data` — the 8B model is ~5GB on disk

## External Access

Open WebUI is accessible from your local network at `http://<server-ip>:3000`.

For external access (family/friends), Open WebUI is exposed via Nginx Proxy Manager — see [`networking/README.md`](../networking/README.md). Once configured it's available at `https://llm.jasonfagerberg.asuscomm.com` from any browser, no app required.

### Setting Up User Accounts

Open WebUI requires account creation on first launch — this also locks it down so only people you've created accounts for can use it.

1. Open `http://<server-ip>:3000` in your browser
2. Create your admin account (first account gets admin)
3. For each family/friend: **Admin Panel > Users > Add User**
   - Set their name, email, and a temporary password
   - Send them the URL and credentials — they can change their password after logging in

### API Access

The Ollama API is protected by the key in `.env` and exposed externally via NPM at `https://llm-api.jasonfagerberg.asuscomm.com`.

Set up the key before starting:
```bash
./generate-env.sh
```

**From your local network:**
```bash
OLLAMA_HOST=http://<server-ip>:11434 OLLAMA_API_KEY=<your-key> ollama run qwen3:8b
```

**From outside your network** — any tool that supports a custom OpenAI-compatible base URL:
```
Base URL: https://llm-api.jasonfagerberg.asuscomm.com
API Key:  <your-key>
Model:    qwen3:8b
```

## Updating

```bash
docker compose pull
docker compose up -d
```
