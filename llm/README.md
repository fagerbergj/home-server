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

For external access (family/friends), Open WebUI is exposed via Nginx Proxy Manager — see [`networking/README.md`](../networking/README.md). Once configured it's available at `https://llm.yourname.asuscomm.com` from any browser, no app required.

### Setting Up User Accounts

Open WebUI requires account creation on first launch — this also locks it down so only people you've created accounts for can use it.

1. Open `http://<server-ip>:3000` in your browser
2. Create your admin account (first account gets admin)
3. For each family/friend: **Admin Panel > Users > Add User**
   - Set their name, email, and a temporary password
   - Send them the URL and credentials — they can change their password after logging in

### API Access

The Ollama API is protected by the key in `.env` and exposed externally via NPM at `https://llm-api.yourname.asuscomm.com`.

Set up the key before starting:
```bash
./generate-env.sh
```

**From your local network:**
```bash
OLLAMA_HOST=http://<server-ip>:11434 OLLAMA_API_KEY=<your-key> ollama run deepseek-r1:7b
```

**From outside your network** — any tool that supports a custom OpenAI-compatible base URL:
```
Base URL: https://llm-api.yourname.asuscomm.com
API Key:  <your-key>
Model:    deepseek-r1:7b
```

## Updating

```bash
docker compose pull
docker compose up -d
```
