# remarkable-bridge

Webhook receiver and OCR processor for the reMarkable → Open WebUI pipeline.

## How it works

1. On the reMarkable tablet, tap the **Share** icon on a notebook and select the bridge integration (configured in rmfakecloud's web UI).
2. rmfakecloud fires a `POST /webhook` (multipart/form-data) containing the note image and metadata.
3. The bridge sends the image to Ollama for OCR, writes the result to disk, and uploads it to an Open WebUI knowledge collection for LLM querying.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/webhook` | rmfakecloud integration target |
| `GET` | `/healthz` | Health check — returns `{"status": "ok"}` |

## Configuration (env vars)

| Variable | Default | Description |
|----------|---------|-------------|
| `OLLAMA_BASE_URL` | `http://ollama:11434` | Ollama API base URL |
| `OCR_MODEL` | `glm-ocr` | Ollama vision model to use for OCR |
| `VAULT_PATH` | `/vault` | Where to write markdown files on disk |
| `OPENWEBUI_URL` | `http://open-webui:8080` | Open WebUI internal URL |
| `OPENWEBUI_API_KEY` | — | Open WebUI API key (Settings → Account → API Keys) |
| `OPENWEBUI_KNOWLEDGE_ID` | — | Knowledge collection ID (Workspace → Knowledge → copy from URL) |

## Output format

Each processed note produces a Markdown file with frontmatter:

```markdown
---
title: "My Note"
date: 2026-03-24
source: remarkable
pages: 1
---

Transcribed text...
```

## Build

```bash
docker build -t remarkable-bridge .
```

## Running tests

```bash
uv run --with pytest --with httpx --with fastapi --with python-multipart \
       --with uvicorn pytest test_app.py -v
```
