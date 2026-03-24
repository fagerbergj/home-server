import io
import json
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
import httpx
from fastapi.testclient import TestClient


# ── fixtures ──────────────────────────────────────────────────────────────────

@pytest.fixture(autouse=True)
def tmp_vault(tmp_path, monkeypatch):
    """Redirect all vault I/O to a temp directory."""
    import app as bridge
    monkeypatch.setattr(bridge, "VAULT_PATH", tmp_path)
    monkeypatch.setattr(bridge, "QUEUE_DIR", tmp_path / "remarkable" / ".queue")
    monkeypatch.setattr(bridge, "NOTES_DIR", tmp_path / "remarkable")
    (tmp_path / "remarkable" / ".queue").mkdir(parents=True)
    return tmp_path


@pytest.fixture
def client(tmp_vault):
    import app as bridge
    # Don't start the real APScheduler in tests
    with patch.object(bridge.scheduler, "start"), \
         patch.object(bridge.scheduler, "add_job"), \
         patch.object(bridge.scheduler, "shutdown"):
        with TestClient(bridge.app) as c:
            yield c


def make_image_upload(filename="image.png", content=b"FAKEPNG"):
    return (filename, io.BytesIO(content), "image/png")


# ── /healthz ──────────────────────────────────────────────────────────────────

def test_healthz(client):
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


# ── /webhook ──────────────────────────────────────────────────────────────────

def test_webhook_queues_single_page(client, tmp_vault):
    import app as bridge

    resp = client.post(
        "/webhook",
        files={"attachment": make_image_upload()},
        data={"data": json.dumps({"title": "My Note", "parent": "Work"})},
    )
    assert resp.status_code == 200
    assert resp.json()["title"] == "My Note"

    queue_entries = list(bridge.QUEUE_DIR.iterdir())
    assert len(queue_entries) == 1
    entry = queue_entries[0]
    assert (entry / "meta.json").exists()
    meta = json.loads((entry / "meta.json").read_text())
    assert meta["title"] == "My Note"
    assert meta["folder_path"] == "Work"


def test_webhook_groups_multi_page_same_title(client, tmp_vault):
    import app as bridge

    for page in range(3):
        resp = client.post(
            "/webhook",
            files={"attachment": make_image_upload(f"p{page}.png")},
            data={"data": json.dumps({"title": "Long Note", "page": page})},
        )
        assert resp.status_code == 200

    queue_entries = list(bridge.QUEUE_DIR.iterdir())
    assert len(queue_entries) == 1, "All pages of one doc must share a queue entry"
    image_files = sorted((queue_entries[0]).glob("image_*.png"))
    assert len(image_files) == 3


def test_webhook_rejects_non_multipart(client):
    resp = client.post("/webhook", json={"title": "oops"})
    assert resp.status_code == 415


def test_webhook_rejects_missing_image(client):
    # Multipart with no file attachment — rmfakecloud always sends multipart
    resp = client.post(
        "/webhook",
        files={"dummy": ("", b"")},  # empty file → not picked up as image
        data={"data": json.dumps({"title": "no image"})},
    )
    assert resp.status_code == 422


def test_webhook_sanitizes_title(client, tmp_vault):
    import app as bridge

    client.post(
        "/webhook",
        files={"attachment": make_image_upload()},
        data={"data": json.dumps({"title": "../../etc/passwd"})},
    )
    entries = list(bridge.QUEUE_DIR.iterdir())
    assert len(entries) == 1
    assert ".." not in entries[0].name


# ── /queue ────────────────────────────────────────────────────────────────────

def test_queue_empty(client):
    resp = client.get("/queue")
    assert resp.status_code == 200
    assert resp.json()["pending"] == 0


def test_queue_counts_entries(client, tmp_vault):
    import app as bridge

    for i in range(3):
        (bridge.QUEUE_DIR / f"note_{i}").mkdir()

    resp = client.get("/queue")
    assert resp.json()["pending"] == 3


# ── OCR job ───────────────────────────────────────────────────────────────────

@pytest.fixture
def mock_ollama():
    """Patch httpx.AsyncClient.post to return a fake Ollama response."""
    fake_response = MagicMock()
    fake_response.raise_for_status = MagicMock()
    fake_response.json.return_value = {"response": "Hello world transcribed"}

    with patch("httpx.AsyncClient.post", new_callable=AsyncMock, return_value=fake_response) as m:
        yield m


@pytest.mark.asyncio
async def test_process_entry_single_page(tmp_vault, mock_ollama):
    import app as bridge
    from app import process_entry

    # Seed a queue entry
    entry = bridge.QUEUE_DIR / "My_Note"
    entry.mkdir(parents=True)
    (entry / "image_0000.png").write_bytes(b"FAKEPNG")
    (entry / "meta.json").write_text(json.dumps({"title": "My Note", "folder_path": ""}))

    await process_entry(entry)

    # Queue entry should be deleted on success
    assert not entry.exists()

    # Markdown file should be created
    md_file = bridge.NOTES_DIR / "My_Note.md"
    assert md_file.exists()
    content = md_file.read_text()
    assert "Hello world transcribed" in content
    assert 'title: "My_Note"' in content
    assert "source: remarkable" in content


@pytest.mark.asyncio
async def test_process_entry_multi_page(tmp_vault, mock_ollama):
    import app as bridge
    from app import process_entry

    entry = bridge.QUEUE_DIR / "Long_Note"
    entry.mkdir(parents=True)
    for i in range(3):
        (entry / f"image_{i:04d}.png").write_bytes(b"FAKEPNG")
    (entry / "meta.json").write_text(json.dumps({"title": "Long Note", "folder_path": ""}))

    await process_entry(entry)

    md_file = bridge.NOTES_DIR / "Long_Note.md"
    content = md_file.read_text()
    # Three pages joined by separator
    assert content.count("Hello world transcribed") == 3
    assert content.count("---") >= 3  # frontmatter + 2 page separators
    assert "pages: 3" in content


@pytest.mark.asyncio
async def test_process_entry_mirrors_folder_structure(tmp_vault, mock_ollama):
    import app as bridge
    from app import process_entry

    entry = bridge.QUEUE_DIR / "Meeting"
    entry.mkdir(parents=True)
    (entry / "image_0000.png").write_bytes(b"FAKEPNG")
    (entry / "meta.json").write_text(json.dumps({"title": "Meeting", "folder_path": "Work/Q1"}))

    await process_entry(entry)

    md_file = bridge.NOTES_DIR / "Work" / "Q1" / "Meeting.md"
    assert md_file.exists()


@pytest.mark.asyncio
async def test_process_entry_leaves_queue_on_failure(tmp_vault):
    import app as bridge
    from app import process_entry

    entry = bridge.QUEUE_DIR / "Bad_Note"
    entry.mkdir(parents=True)
    (entry / "image_0000.png").write_bytes(b"FAKEPNG")
    (entry / "meta.json").write_text(json.dumps({"title": "Bad Note", "folder_path": ""}))

    with patch("httpx.AsyncClient.post", new_callable=AsyncMock, side_effect=httpx.HTTPError("timeout")):
        with pytest.raises(httpx.HTTPError):
            await process_entry(entry)

    # Entry should still exist for retry next night
    assert entry.exists()


@pytest.mark.asyncio
async def test_process_entry_skips_missing_meta(tmp_vault):
    import app as bridge
    from app import process_entry

    entry = bridge.QUEUE_DIR / "No_Meta"
    entry.mkdir(parents=True)
    (entry / "image_0000.png").write_bytes(b"FAKEPNG")
    # No meta.json

    await process_entry(entry)  # Should log warning and return, not raise

    # Nothing written to notes dir
    assert not any(bridge.NOTES_DIR.glob("*.md"))


# ── /jobs/ocr ─────────────────────────────────────────────────────────────────

def test_jobs_ocr_empty_queue(client):
    resp = client.post("/jobs/ocr")
    assert resp.status_code == 200
    assert resp.json()["processed"] == 0
