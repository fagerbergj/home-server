import base64
import json
import logging
import os
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path

import httpx
from fastapi import FastAPI, HTTPException, Request

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

OLLAMA_BASE_URL = os.environ.get("OLLAMA_BASE_URL", "http://ollama:11434")
OCR_MODEL = os.environ.get("OCR_MODEL", "qwen2.5vl:7b")
VAULT_PATH = Path(os.environ.get("VAULT_PATH", "/vault"))

NOTES_DIR = VAULT_PATH / "remarkable"

OCR_PROMPT = (
    "You are an OCR engine. Transcribe all handwritten and printed text in this image "
    "exactly as written. Preserve paragraph structure with blank lines between paragraphs. "
    "Output only the transcribed text — no commentary, no explanations."
)

_GENERIC_FILENAMES = {"remarkable", "untitled", "image", "attachment", "document"}


def sanitize(name: str) -> str:
    safe = "".join(c if c.isalnum() or c in "_-" else "_" for c in name)
    return safe.strip("_") or "untitled"


def extract_title(meta_json: dict, attachment_filename: str | None, ocr_text: str) -> str:
    # destinations from rmfakecloud data field
    for dest in meta_json.get("destinations", []):
        name = str(dest).strip()
        if name:
            return name

    # attachment filename (skip generic names)
    if attachment_filename:
        stem = Path(attachment_filename).stem
        if stem and stem.lower() not in _GENERIC_FILENAMES:
            return stem

    # first line of OCR text
    for line in ocr_text.splitlines():
        line = line.strip()
        if line and len(line) <= 80:
            return line

    return datetime.now(timezone.utc).strftime("%Y-%m-%d_%H%M%S")


@asynccontextmanager
async def lifespan(_app: FastAPI):
    NOTES_DIR.mkdir(parents=True, exist_ok=True)
    logger.info("remarkable-bridge started. model: %s", OCR_MODEL)
    yield


app = FastAPI(title="remarkable-bridge", lifespan=lifespan)


@app.get("/healthz")
async def healthz():
    return {"status": "ok"}


@app.post("/webhook")
async def webhook(request: Request):
    """
    Receives a document send from the reMarkable tablet via rmfakecloud integrations.
    rmfakecloud posts multipart/form-data with:
      - data:       JSON string with document metadata
      - attachment: rendered PNG image of the current sheet
    """
    content_type = request.headers.get("content-type", "")
    if "multipart/form-data" not in content_type:
        raise HTTPException(status_code=415, detail="Expected multipart/form-data")

    form = await request.form()

    meta_raw = form.get("data") or "{}"
    try:
        meta_json = json.loads(str(meta_raw))
    except json.JSONDecodeError:
        meta_json = {}

    folder_path = str(
        meta_json.get("parent") or meta_json.get("folder")
        or form.get("parent") or form.get("folder") or ""
    )

    attachment = form.get("attachment")
    attachment_filename: str | None = None
    image_bytes: bytes | None = None
    if attachment and hasattr(attachment, "read"):
        attachment_filename = getattr(attachment, "filename", None)
        image_bytes = await attachment.read()
    else:
        for key in form:
            field = form[key]
            if hasattr(field, "read"):
                raw = await field.read()
                if raw:
                    attachment_filename = getattr(field, "filename", None)
                    image_bytes = raw
                    break

    if not image_bytes:
        raise HTTPException(status_code=422, detail="No image attachment found")

    logger.info("Webhook: received %d bytes (folder: '%s')", len(image_bytes), folder_path)

    async with httpx.AsyncClient(timeout=120.0) as client:
        try:
            title = await ocr_and_write(
                client, meta_json, attachment_filename, folder_path, [image_bytes]
            )
        except Exception as exc:
            logger.error("OCR failed: %s", exc)
            raise HTTPException(status_code=500, detail=str(exc))

    return {"status": "ok", "title": title}


async def ocr_and_write(
    client: httpx.AsyncClient,
    meta_json: dict,
    attachment_filename: str | None,
    folder_path: str,
    page_images: list[bytes],
) -> str:
    page_texts: list[str] = []
    for i, img_bytes in enumerate(page_images):
        image_b64 = base64.b64encode(img_bytes).decode("utf-8")
        resp = await client.post(
            f"{OLLAMA_BASE_URL}/api/generate",
            json={
                "model": OCR_MODEL,
                "prompt": OCR_PROMPT,
                "images": [image_b64],
                "stream": False,
            },
        )
        if resp.is_error:
            logger.error("Ollama error %s: %s", resp.status_code, resp.text)
        resp.raise_for_status()
        text = resp.json().get("response", "").strip()
        page_texts.append(text or "(no text recognised)")
        logger.info("  page %d: %d chars", i + 1, len(page_texts[-1]))

    ocr_text = "\n\n---\n\n".join(page_texts)
    title = extract_title(meta_json, attachment_filename, ocr_text)
    logger.info("Title: '%s'", title)

    safe_folder = (
        Path(*[sanitize(part) for part in Path(folder_path).parts])
        if folder_path
        else Path()
    )
    out_dir = NOTES_DIR / safe_folder
    out_dir.mkdir(parents=True, exist_ok=True)

    date_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    md = f"""---
title: "{title}"
date: {date_str}
source: remarkable
pages: {len(page_images)}
---

{ocr_text}
"""
    (out_dir / f"{sanitize(title)}.md").write_text(md, encoding="utf-8")
    logger.info("Written: %s", out_dir / f"{sanitize(title)}.md")
    return title
