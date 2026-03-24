# remarkable-bridge

Webhook receiver and OCR processor for the reMarkable → Obsidian pipeline.

## How it works

1. On the reMarkable tablet, tap the **Share** icon on a notebook and select the bridge integration (configured in rmfakecloud's web UI).
2. rmfakecloud fires a `POST /webhook` (multipart/form-data) containing the note image and metadata.
3. The bridge sends the image to Ollama's vision API for OCR and writes the result to `/vault/remarkable/<folder-path>/<title>.md`, mirroring the notebook's folder structure from the reMarkable.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/webhook` | rmfakecloud integration target |
| `GET` | `/healthz` | Health check — returns `{"status": "ok"}` |

## Configuration (env vars)

| Variable | Default | Description |
|----------|---------|-------------|
| `OLLAMA_BASE_URL` | `http://ollama:11434` | Ollama API base URL |
| `OCR_MODEL` | `qwen2.5vl:7b` | Ollama vision model to use for OCR |
| `VAULT_PATH` | `/vault` | Mount point of the Obsidian vault |

## Output format

Each processed document produces a Markdown file with frontmatter:

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
