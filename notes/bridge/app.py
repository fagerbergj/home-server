import base64
import io
import json
import logging
import os
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path

import httpx
import pypdfium2 as pdfium
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from fastapi import FastAPI, HTTPException

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

OLLAMA_BASE_URL = os.environ.get("OLLAMA_BASE_URL", "http://ollama:11434")
OCR_MODEL = os.environ.get("OCR_MODEL", "richardyoung/olmocr2:7b-q8")
VAULT_PATH = Path(os.environ.get("VAULT_PATH", "/vault"))
RMFAKECLOUD_URL = os.environ.get("RMFAKECLOUD_URL", "http://rmfakecloud:3000")
RMFAKECLOUD_USER = os.environ.get("RMFAKECLOUD_USER", "")
RMFAKECLOUD_PASSWORD = os.environ.get("RMFAKECLOUD_PASSWORD", "")

NOTES_DIR = VAULT_PATH / "remarkable"
STATE_FILE = NOTES_DIR / ".processed.json"

OCR_PROMPT = (
    "You are an OCR engine. Transcribe all handwritten and printed text in this image "
    "exactly as written. Preserve paragraph structure with blank lines between paragraphs. "
    "Output only the transcribed text — no commentary, no explanations."
)

scheduler = AsyncIOScheduler()


def sanitize(name: str) -> str:
    safe = "".join(c if c.isalnum() or c in "_-" else "_" for c in name)
    return safe.strip("_") or "untitled"


def load_state() -> dict:
    if STATE_FILE.exists():
        try:
            return json.loads(STATE_FILE.read_text(encoding="utf-8"))
        except Exception:
            return {}
    return {}


def save_state(state: dict) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, indent=2), encoding="utf-8")


def pdf_to_images(pdf_bytes: bytes) -> list[bytes]:
    """Convert each PDF page to a PNG at 2× scale (better OCR accuracy)."""
    doc = pdfium.PdfDocument(pdf_bytes)
    images = []
    for page in doc:
        bitmap = page.render(scale=2)
        pil_image = bitmap.to_pil()
        buf = io.BytesIO()
        pil_image.save(buf, format="PNG")
        images.append(buf.getvalue())
    return images


def build_folder_path(entries: list[dict], parent_id: str) -> str:
    """Walk collection entries upward to produce a slash-separated folder path."""
    id_to_entry = {
        (e.get("ID") or e.get("id") or ""): e for e in entries
    }
    parts: list[str] = []
    current = parent_id
    visited: set[str] = set()
    while current and current not in visited:
        visited.add(current)
        entry = id_to_entry.get(current)
        if not entry:
            break
        name = (
            entry.get("Name")
            or entry.get("name")
            or entry.get("VissibleName")
            or ""
        )
        if name:
            parts.insert(0, name)
        current = entry.get("Parent") or entry.get("parent") or ""
    return "/".join(parts)


@asynccontextmanager
async def lifespan(_app: FastAPI):
    NOTES_DIR.mkdir(parents=True, exist_ok=True)
    scheduler.add_job(run_sync_and_ocr_job, "cron", hour=2, minute=0)
    scheduler.start()
    logger.info(
        "remarkable-bridge started. model: %s, rmfakecloud: %s",
        OCR_MODEL,
        RMFAKECLOUD_URL,
    )
    yield
    scheduler.shutdown()


app = FastAPI(title="remarkable-bridge", lifespan=lifespan)


@app.post("/jobs/ocr")
async def trigger_ocr():
    if not RMFAKECLOUD_USER or not RMFAKECLOUD_PASSWORD:
        raise HTTPException(
            status_code=503,
            detail="RMFAKECLOUD_USER and RMFAKECLOUD_PASSWORD must be set",
        )
    await run_sync_and_ocr_job()
    return {"status": "ok"}


@app.get("/queue")
async def queue_status():
    state = load_state()
    return {"processed": len(state)}


@app.get("/healthz")
async def healthz():
    return {"status": "ok"}


# ── rmfakecloud API helpers ────────────────────────────────────────────────────


async def rmfakecloud_login(client: httpx.AsyncClient) -> str:
    """Authenticate and return the JWT token."""
    resp = await client.post(
        f"{RMFAKECLOUD_URL}/ui/api/login",
        json={"email": RMFAKECLOUD_USER, "password": RMFAKECLOUD_PASSWORD},
    )
    resp.raise_for_status()
    return resp.text.strip()


async def list_documents(client: httpx.AsyncClient, token: str) -> dict:
    resp = await client.get(
        f"{RMFAKECLOUD_URL}/ui/api/documents",
        headers={"Authorization": f"Bearer {token}"},
    )
    resp.raise_for_status()
    return resp.json()


async def download_document_pdf(
    client: httpx.AsyncClient, token: str, doc_id: str
) -> bytes:
    resp = await client.get(
        f"{RMFAKECLOUD_URL}/ui/api/documents/{doc_id}",
        params={"type": "pdf"},
        headers={"Authorization": f"Bearer {token}"},
    )
    resp.raise_for_status()
    return resp.content


# ── main job ──────────────────────────────────────────────────────────────────


async def run_sync_and_ocr_job() -> None:
    if not RMFAKECLOUD_USER or not RMFAKECLOUD_PASSWORD:
        logger.error("RMFAKECLOUD_USER/PASSWORD not set — skipping job")
        return

    logger.info("Sync+OCR job: authenticating with rmfakecloud at %s", RMFAKECLOUD_URL)

    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            token = await rmfakecloud_login(client)
        except Exception as exc:
            logger.error("Login failed: %s", exc)
            return

        try:
            tree = await list_documents(client, token)
        except Exception as exc:
            logger.error("Failed to list documents: %s", exc)
            return

    all_entries: list[dict] = (tree.get("Entries") or []) + (tree.get("entries") or [])
    state = load_state()

    documents = [
        e
        for e in all_entries
        if (e.get("Type") or e.get("type") or "") == "DocumentType"
    ]
    new_docs = [
        d for d in documents if (d.get("ID") or d.get("id") or "") not in state
    ]

    if not new_docs:
        logger.info("Sync+OCR job: no new documents")
        return

    logger.info("Sync+OCR job: %d new document(s) to process", len(new_docs))

    async with httpx.AsyncClient(timeout=300.0) as client:
        for doc in new_docs:
            doc_id = doc.get("ID") or doc.get("id") or ""
            title = (
                doc.get("Name")
                or doc.get("name")
                or doc.get("VissibleName")
                or "untitled"
            )
            parent_id = doc.get("Parent") or doc.get("parent") or ""
            folder_path = build_folder_path(all_entries, parent_id)

            try:
                await process_document(client, token, doc_id, title, folder_path)
                state[doc_id] = {
                    "title": title,
                    "processed_at": datetime.now(timezone.utc).isoformat(),
                    "folder_path": folder_path,
                }
                save_state(state)
                logger.info("Processed: '%s' (%s)", title, doc_id)
            except Exception as exc:
                logger.error("Failed to process '%s' (%s): %s", title, doc_id, exc)


async def process_document(
    client: httpx.AsyncClient,
    token: str,
    doc_id: str,
    title: str,
    folder_path: str,
) -> None:
    logger.info("Downloading '%s' as PDF", title)
    pdf_bytes = await download_document_pdf(client, token, doc_id)

    logger.info("Converting PDF to images (%d bytes)", len(pdf_bytes))
    page_images = pdf_to_images(pdf_bytes)
    logger.info("'%s': %d page(s)", title, len(page_images))

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
        resp.raise_for_status()
        text = resp.json().get("response", "").strip()
        page_texts.append(text or "(no text recognised)")
        logger.info("  page %d: %d chars", i + 1, len(page_texts[-1]))

    ocr_text = "\n\n---\n\n".join(page_texts)

    safe_folder = (
        Path(*[sanitize(part) for part in Path(folder_path).parts])
        if folder_path
        else Path()
    )
    out_dir = NOTES_DIR / safe_folder
    out_dir.mkdir(parents=True, exist_ok=True)

    date_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    md = f"""---
title: "{sanitize(title)}"
date: {date_str}
source: remarkable
pages: {len(page_images)}
---

{ocr_text}
"""
    (out_dir / f"{sanitize(title)}.md").write_text(md, encoding="utf-8")
    logger.info("Written: %s", out_dir / f"{sanitize(title)}.md")
