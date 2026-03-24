import base64
import io
import json
import logging
import os
import zipfile
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path

import cairosvg
import httpx
import pypdfium2 as pdfium
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from fastapi import FastAPI, HTTPException, Request
from rmscene import read_tree
from rmc.exporters.svg import tree_to_svg

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


def rm_bytes_to_png(rm_bytes: bytes) -> bytes:
    """Render a single .rm page to PNG via SVG."""
    tree = read_tree(io.BytesIO(rm_bytes))
    svg_buf = io.StringIO()
    tree_to_svg(tree, svg_buf)
    return cairosvg.svg2png(bytestring=svg_buf.getvalue().encode(), scale=1.0, background_color="white")


def rmdoc_to_images(rmdoc_bytes: bytes) -> list[bytes]:
    """Extract .rm pages from an rmdoc ZIP and render each to PNG."""
    with zipfile.ZipFile(io.BytesIO(rmdoc_bytes)) as zf:
        names = zf.namelist()

        # Determine page order from the .content JSON if present
        page_ids: list[str] = []
        content_files = [n for n in names if n.endswith(".content")]
        if content_files:
            try:
                content = json.loads(zf.read(content_files[0]))
                # Newer format: cPages.pages[].id; older: pages[]
                cpages = content.get("cPages", {}).get("pages", [])
                if cpages:
                    page_ids = [p["id"] for p in cpages if "id" in p]
                else:
                    page_ids = content.get("pages", [])
            except Exception:
                pass

        rm_files = [n for n in names if n.endswith(".rm")]
        if page_ids:
            stem_to_path = {Path(n).stem: n for n in rm_files}
            ordered = [stem_to_path[pid] for pid in page_ids if pid in stem_to_path]
            rm_files = ordered if ordered else sorted(rm_files)
        else:
            rm_files = sorted(rm_files)

        images = []
        for rm_name in rm_files:
            try:
                images.append(rm_bytes_to_png(zf.read(rm_name)))
            except Exception as exc:
                logger.warning("Could not render page %s: %s", rm_name, exc)

    return images


def flatten_tree(entries: list[dict], folder_path: str = "") -> list[tuple[dict, str]]:
    """Recursively flatten the document tree into (entry, folder_path) pairs."""
    results = []
    for entry in entries:
        if entry.get("isFolder"):
            name = entry.get("name") or ""
            child_path = f"{folder_path}/{name}" if folder_path else name
            results.extend(flatten_tree(entry.get("children") or [], child_path))
        elif entry.get("type") in ("notebook", "pdf"):
            results.append((entry, folder_path))
    return results


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


@app.post("/webhook")
async def webhook(request: Request):
    """
    Receives a document send from the reMarkable tablet via rmfakecloud integrations.
    rmfakecloud posts multipart/form-data with two fields:
      - data:       JSON string with document metadata (title, parent/folder)
      - attachment: rendered PNG image of the current sheet
    OCR runs immediately on receipt.
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

    title = str(
        meta_json.get("title") or meta_json.get("name")
        or form.get("title") or form.get("name") or "untitled"
    )
    folder_path = str(
        meta_json.get("parent") or meta_json.get("folder")
        or form.get("parent") or form.get("folder") or ""
    )

    attachment = form.get("attachment")
    image_bytes: bytes | None = None
    if attachment and hasattr(attachment, "read"):
        image_bytes = await attachment.read()
    else:
        for key in form:
            field = form[key]
            if hasattr(field, "read"):
                raw = await field.read()
                if raw:
                    image_bytes = raw
                    break

    if not image_bytes:
        raise HTTPException(status_code=422, detail="No image attachment found")

    logger.info("Webhook: '%s' in '%s' (%d bytes) — OCR starting", title, folder_path, len(image_bytes))

    async with httpx.AsyncClient(timeout=120.0) as client:
        await process_document_images(client, title, folder_path, [image_bytes])

    return {"status": "ok", "title": title}


@app.post("/jobs/ocr")
async def trigger_ocr(doc_id: str | None = None):
    if not RMFAKECLOUD_USER or not RMFAKECLOUD_PASSWORD:
        raise HTTPException(
            status_code=503,
            detail="RMFAKECLOUD_USER and RMFAKECLOUD_PASSWORD must be set",
        )
    await run_sync_and_ocr_job(only_doc_id=doc_id)
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


async def download_document(
    client: httpx.AsyncClient, token: str, doc_id: str, fmt: str
) -> bytes:
    resp = await client.get(
        f"{RMFAKECLOUD_URL}/ui/api/documents/{doc_id}",
        params={"type": fmt},
        headers={"Authorization": f"Bearer {token}"},
    )
    resp.raise_for_status()
    return resp.content


# ── main job ──────────────────────────────────────────────────────────────────


async def run_sync_and_ocr_job(only_doc_id: str | None = None) -> None:
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

    all_entries: list[dict] = tree.get("Entries") or []
    state = load_state()

    documents_with_paths = flatten_tree(all_entries)
    new_docs = [
        (doc, path)
        for doc, path in documents_with_paths
        if (only_doc_id and doc["id"] == only_doc_id)
        or (
            not only_doc_id
            and (
                doc["id"] not in state
                or doc.get("lastModified", "") > state[doc["id"]].get("last_modified", "")
            )
        )
    ]

    if not new_docs:
        logger.info("Sync+OCR job: no new documents")
        return

    logger.info("Sync+OCR job: %d new document(s) to process", len(new_docs))

    async with httpx.AsyncClient(timeout=300.0) as client:
        for doc, folder_path in new_docs:
            doc_id = doc["id"]
            title = doc.get("name") or "untitled"

            try:
                await process_document(client, token, doc_id, title, folder_path)
                state[doc_id] = {
                    "title": title,
                    "processed_at": datetime.now(timezone.utc).isoformat(),
                    "folder_path": folder_path,
                    "last_modified": doc.get("lastModified", ""),
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
    pdf_bytes = await download_document(client, token, doc_id, "pdf")

    if pdf_bytes:
        logger.info("Converting PDF to images (%d bytes)", len(pdf_bytes))
        page_images = pdf_to_images(pdf_bytes)
    else:
        logger.info("PDF empty for '%s', falling back to rmdoc rendering", title)
        rmdoc_bytes = await download_document(client, token, doc_id, "rmdoc")
        page_images = rmdoc_to_images(rmdoc_bytes)

    if not page_images:
        raise ValueError(f"No pages rendered for '{title}'")

    await process_document_images(client, title, folder_path, page_images)


async def process_document_images(
    client: httpx.AsyncClient,
    title: str,
    folder_path: str,
    page_images: list[bytes],
) -> None:
    """OCR a list of page images and write the result as a Markdown file."""
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
        if resp.is_error:
            logger.error("Ollama error %s: %s", resp.status_code, resp.text)
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
