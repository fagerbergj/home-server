# remarkable-bridge

Webhook receiver and nightly OCR processor for the reMarkable → Obsidian pipeline.

## How it works

1. **Receive** — rmfakecloud fires a `POST /webhook` (multipart/form-data) each time a page is synced from the tablet. The bridge extracts the page image and saves it to a queue directory, grouped by document title. Multi-page notebooks accumulate in a single queue entry.

2. **Process** — At 02:00 every night, the bridge iterates the queue. For each document, it sends every page image to Ollama's vision API (`/api/generate`) in order, collects the OCR text, and concatenates pages with `---` separators into a single `.md` file. The file is written to `/vault/remarkable/<folder-path>/<title>.md`, mirroring the notebook's folder structure from the reMarkable.

3. **Clean up** — On success, the queue entry is deleted. On failure (Ollama timeout, OOM, etc.), the entry is left in place and retried the following night.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/webhook` | rmfakecloud integration target — queues a page image |
| `POST` | `/jobs/ocr` | Trigger the OCR job immediately (useful for testing) |
| `GET` | `/queue` | Returns `{"pending": N}` — count of documents waiting in queue |
| `GET` | `/healthz` | Health check — returns `{"status": "ok"}` |

## Configuration (env vars)

| Variable | Default | Description |
|----------|---------|-------------|
| `OLLAMA_BASE_URL` | `http://ollama:11434` | Ollama API base URL (loaded from root `.env`) |
| `OCR_MODEL` | `richardyoung/olmocr2:7b-q8` | Ollama model to use for OCR |
| `VAULT_PATH` | `/vault` | Mount point of the Obsidian vault |

## Output format

Each processed document produces a Markdown file with frontmatter:

```markdown
---
title: "My Note"
date: 2026-03-24
source: remarkable
pages: 3
---

Page 1 transcribed text...

---

Page 2 transcribed text...

---

Page 3 transcribed text...
```

## Running tests

```bash
uv run --with pytest --with pytest-asyncio --with httpx --with fastapi \
       --with apscheduler --with python-multipart --with uvicorn \
       pytest test_app.py -v
```
