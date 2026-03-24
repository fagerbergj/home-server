import base64
import json
import logging
import os
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path

import httpx
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from fastapi import FastAPI, HTTPException, Request

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

OLLAMA_BASE_URL = os.environ.get("OLLAMA_BASE_URL", "http://ollama:11434")
OCR_MODEL = os.environ.get("OCR_MODEL", "richardyoung/olmocr2:7b-q8")
VAULT_PATH = Path(os.environ.get("VAULT_PATH", "/vault"))

QUEUE_DIR = VAULT_PATH / "remarkable" / ".queue"
NOTES_DIR = VAULT_PATH / "remarkable"

OCR_PROMPT = (
    "You are an OCR engine. Transcribe all handwritten and printed text in this image "
    "exactly as written. Preserve paragraph structure with blank lines between paragraphs. "
    "Output only the transcribed text — no commentary, no explanations."
)

scheduler = AsyncIOScheduler()


def sanitize(name: str) -> str:
    safe = "".join(c if c.isalnum() or c in "_-" else "_" for c in name)
    return safe.strip("_") or "untitled"


@asynccontextmanager
async def lifespan(_app: FastAPI):
    QUEUE_DIR.mkdir(parents=True, exist_ok=True)
    scheduler.add_job(run_ocr_job, "cron", hour=2, minute=0)
    scheduler.start()
    logger.info("remarkable-bridge started. model: %s, queue: %s", OCR_MODEL, QUEUE_DIR)
    yield
    scheduler.shutdown()


app = FastAPI(title="remarkable-bridge", lifespan=lifespan)


@app.post("/webhook")
async def webhook(request: Request):
    content_type = request.headers.get("content-type", "")
    if "multipart/form-data" not in content_type:
        raise HTTPException(status_code=415, detail="Expected multipart/form-data")

    form = await request.form()

    # rmfakecloud sends two fields: "data" (JSON metadata) and "attachment" (PNG image)
    meta_raw = form.get("data") or "{}"
    try:
        meta_json = json.loads(str(meta_raw))
    except json.JSONDecodeError:
        meta_json = {}

    title = str(meta_json.get("title") or meta_json.get("name") or
                form.get("title") or form.get("name") or "untitled")
    folder_path = str(meta_json.get("parent") or meta_json.get("folder") or
                      form.get("parent") or form.get("folder") or "")
    page = int(meta_json.get("page") or meta_json.get("pageNumber") or
               form.get("page") or form.get("pageNumber") or 0)

    # "attachment" is the known field name; fall back to scanning all upload fields
    attachment = form.get("attachment")
    image_bytes: bytes | None = None
    image_ext = "png"
    if attachment and hasattr(attachment, "read"):
        image_bytes = await attachment.read()
        if hasattr(attachment, "content_type") and attachment.content_type:
            image_ext = attachment.content_type.split("/")[-1] or "png"
        logger.info("Image from 'attachment' field, %d bytes", len(image_bytes))
    else:
        for key in form:
            field = form[key]
            if hasattr(field, "read"):
                raw = await field.read()
                if raw:
                    image_bytes = raw
                    if hasattr(field, "content_type") and field.content_type:
                        image_ext = field.content_type.split("/")[-1] or "png"
                    logger.info("Image from fallback field '%s', %d bytes", key, len(image_bytes))
                    break

    if not image_bytes:
        raise HTTPException(status_code=422, detail="No image attachment found in webhook payload")

    # Group pages of the same document into one queue entry by title.
    # Each page is stored as image_<page>.ext inside the entry directory.
    queue_entry = QUEUE_DIR / sanitize(title)
    queue_entry.mkdir(parents=True, exist_ok=True)

    (queue_entry / f"image_{page:04d}.{image_ext}").write_bytes(image_bytes)

    # Write/update meta (safe to overwrite; folder_path and title don't change across pages)
    (queue_entry / "meta.json").write_text(
        json.dumps({"title": title, "folder_path": folder_path}),
        encoding="utf-8",
    )

    logger.info("Queued note '%s' page %d in folder '%s'", title, page, folder_path)
    return {"status": "queued", "title": title, "page": page}


@app.post("/jobs/ocr")
async def trigger_ocr():
    pending = sum(1 for p in QUEUE_DIR.iterdir() if p.is_dir()) if QUEUE_DIR.exists() else 0
    if pending == 0:
        return {"status": "ok", "processed": 0, "message": "queue is empty"}
    await run_ocr_job()
    return {"status": "ok", "message": f"processed {pending} note(s)"}


@app.get("/queue")
async def queue_status():
    count = sum(1 for p in QUEUE_DIR.iterdir() if p.is_dir()) if QUEUE_DIR.exists() else 0
    return {"pending": count}


@app.get("/healthz")
async def healthz():
    return {"status": "ok"}


async def run_ocr_job():
    if not QUEUE_DIR.exists():
        return

    entries = [p for p in QUEUE_DIR.iterdir() if p.is_dir()]
    if not entries:
        logger.info("OCR job: queue is empty")
        return

    logger.info("OCR job: processing %d note(s)", len(entries))

    for entry in entries:
        try:
            await process_entry(entry)
        except Exception as exc:
            logger.error("Failed to process %s: %s", entry.name, exc)


async def process_entry(entry: Path):
    meta_file = entry / "meta.json"
    if not meta_file.exists():
        logger.warning("Skipping %s: no meta.json", entry.name)
        return

    meta = json.loads(meta_file.read_text(encoding="utf-8"))
    title = meta.get("title", "untitled")
    folder_path = meta.get("folder_path", "")

    # Sort pages by filename (image_0000.png, image_0001.png, ...)
    image_files = sorted(entry.glob("image_*.*"))
    if not image_files:
        logger.warning("Skipping %s: no image files", entry.name)
        return

    logger.info("OCR: '%s' (%d page(s)) via %s", title, len(image_files), OCR_MODEL)

    page_texts: list[str] = []
    async with httpx.AsyncClient(timeout=120.0) as client:
        for img_path in image_files:
            image_b64 = base64.b64encode(img_path.read_bytes()).decode("utf-8")
            resp = await client.post(
                f"{OLLAMA_BASE_URL}/api/generate",
                json={"model": OCR_MODEL, "prompt": OCR_PROMPT, "images": [image_b64], "stream": False},
            )
            resp.raise_for_status()
            text = resp.json().get("response", "").strip()
            page_texts.append(text or "(no text recognised)")
            logger.info("  page %s done (%d chars)", img_path.name, len(page_texts[-1]))

    # Join pages with a separator so multi-page docs read naturally
    ocr_text = "\n\n---\n\n".join(page_texts)

    # Mirror reMarkable folder structure under /vault/remarkable/
    safe_folder = Path(*[sanitize(part) for part in Path(folder_path).parts]) if folder_path else Path()
    out_dir = NOTES_DIR / safe_folder
    out_dir.mkdir(parents=True, exist_ok=True)

    date_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    md = f"""---
title: "{sanitize(title)}"
date: {date_str}
source: remarkable
pages: {len(image_files)}
---

{ocr_text}
"""
    (out_dir / f"{sanitize(title)}.md").write_text(md, encoding="utf-8")
    logger.info("Written: %s", out_dir / f"{sanitize(title)}.md")

    # Remove queue entry on success
    for f in entry.iterdir():
        f.unlink()
    entry.rmdir()
