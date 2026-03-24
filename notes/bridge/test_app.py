import io
import json
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest
from fastapi.testclient import TestClient


# ── fixtures ──────────────────────────────────────────────────────────────────


@pytest.fixture(autouse=True)
def tmp_vault(tmp_path, monkeypatch):
    """Redirect all vault I/O to a temp directory."""
    import app as bridge

    monkeypatch.setattr(bridge, "VAULT_PATH", tmp_path)
    monkeypatch.setattr(bridge, "NOTES_DIR", tmp_path / "remarkable")
    monkeypatch.setattr(bridge, "STATE_FILE", tmp_path / "remarkable" / ".processed.json")
    monkeypatch.setattr(bridge, "RMFAKECLOUD_USER", "user@example.com")
    monkeypatch.setattr(bridge, "RMFAKECLOUD_PASSWORD", "secret")
    (tmp_path / "remarkable").mkdir(parents=True)
    return tmp_path


@pytest.fixture
def client(tmp_vault):
    import app as bridge

    with (
        patch.object(bridge.scheduler, "start"),
        patch.object(bridge.scheduler, "add_job"),
        patch.object(bridge.scheduler, "shutdown"),
    ):
        with TestClient(bridge.app) as c:
            yield c


def make_tree(entries: list[dict]) -> dict:
    """Build a fake DocumentTree response."""
    return {"Entries": entries, "Trash": []}


def make_doc(doc_id: str, name: str) -> dict:
    return {"id": doc_id, "name": name, "type": "notebook"}


def make_folder(name: str, children: list[dict]) -> dict:
    return {"name": name, "isFolder": True, "children": children}


@pytest.fixture
def mock_ollama():
    """Patch httpx.AsyncClient.post to return a fake Ollama response."""
    fake = MagicMock()
    fake.raise_for_status = MagicMock()
    fake.json.return_value = {"response": "Hello world transcribed"}
    with patch("httpx.AsyncClient.post", new_callable=AsyncMock, return_value=fake) as m:
        yield m


# ── /healthz ──────────────────────────────────────────────────────────────────


def test_healthz(client):
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


# ── /webhook ──────────────────────────────────────────────────────────────────


def test_webhook_rejects_non_multipart(client):
    resp = client.post("/webhook", json={"title": "oops"})
    assert resp.status_code == 415


def test_webhook_rejects_missing_image(client):
    resp = client.post(
        "/webhook",
        files={"dummy": ("", b"")},
        data={"data": json.dumps({"title": "no image"})},
    )
    assert resp.status_code == 422


def test_webhook_ocrs_and_writes_md(client, tmp_vault, mock_ollama):
    import app as bridge

    with patch("app.process_document_images", new_callable=AsyncMock) as mock_process:
        resp = client.post(
            "/webhook",
            files={"attachment": ("sheet.png", io.BytesIO(b"FAKEPNG"), "image/png")},
            data={"data": json.dumps({"title": "My Sheet", "parent": "Work"})},
        )

    assert resp.status_code == 200
    assert resp.json()["title"] == "My Sheet"
    mock_process.assert_called_once()
    call_kwargs = mock_process.call_args
    assert call_kwargs.args[1] == "My Sheet"
    assert call_kwargs.args[2] == "Work"
    assert call_kwargs.args[3] == [b"FAKEPNG"]


# ── /queue ────────────────────────────────────────────────────────────────────


def test_queue_empty(client):
    resp = client.get("/queue")
    assert resp.status_code == 200
    assert resp.json()["processed"] == 0


def test_queue_reflects_state_file(client, tmp_vault):
    import app as bridge

    state = {
        "doc-1": {"title": "Note 1", "processed_at": "2026-01-01", "folder_path": ""},
        "doc-2": {"title": "Note 2", "processed_at": "2026-01-02", "folder_path": "Work"},
    }
    bridge.STATE_FILE.write_text(json.dumps(state))

    resp = client.get("/queue")
    assert resp.json()["processed"] == 2


# ── /jobs/ocr ─────────────────────────────────────────────────────────────────


def test_jobs_ocr_missing_credentials(client, monkeypatch):
    import app as bridge

    monkeypatch.setattr(bridge, "RMFAKECLOUD_USER", "")
    monkeypatch.setattr(bridge, "RMFAKECLOUD_PASSWORD", "")

    resp = client.post("/jobs/ocr")
    assert resp.status_code == 503


def test_jobs_ocr_triggers_job(client):
    with patch("app.run_sync_and_ocr_job", new_callable=AsyncMock) as mock_job:
        resp = client.post("/jobs/ocr")
    assert resp.status_code == 200
    mock_job.assert_called_once()


# ── sanitize ──────────────────────────────────────────────────────────────────


def test_sanitize_spaces_become_underscores():
    from app import sanitize

    assert sanitize("My Note") == "My_Note"


def test_sanitize_strips_path_traversal():
    from app import sanitize

    assert ".." not in sanitize("../../etc/passwd")


def test_sanitize_empty_falls_back():
    from app import sanitize

    assert sanitize("!!!") == "untitled"


# ── flatten_tree ──────────────────────────────────────────────────────────────


def test_flatten_tree_root_doc():
    from app import flatten_tree

    entries = [make_doc("d1", "Note")]
    flat = flatten_tree(entries)
    assert flat == [({'id': 'd1', 'name': 'Note', 'type': 'notebook'}, "")]


def test_flatten_tree_flat_folder():
    from app import flatten_tree

    entries = [make_folder("Work", [make_doc("d1", "Note")])]
    flat = flatten_tree(entries)
    assert flat[0][1] == "Work"


def test_flatten_tree_nested_folder():
    from app import flatten_tree

    entries = [make_folder("Work", [make_folder("Q1", [make_doc("d1", "Meeting")])])]
    flat = flatten_tree(entries)
    assert flat[0][1] == "Work/Q1"


def test_flatten_tree_empty_folder():
    from app import flatten_tree

    entries = [make_folder("Empty", [])]
    assert flatten_tree(entries) == []


# ── run_sync_and_ocr_job ──────────────────────────────────────────────────────


@pytest.fixture
def fake_pdf_images():
    """Patch pdf_to_images to return two fake PNG pages."""
    with patch("app.pdf_to_images", return_value=[b"FAKEPNG1", b"FAKEPNG2"]) as m:
        yield m


def fake_http(tree: dict, pdf: bytes = b"FAKEPDF"):
    """Return a context manager that patches httpx.AsyncClient to fake rmfakecloud + Ollama."""
    login_resp = MagicMock()
    login_resp.raise_for_status = MagicMock()
    login_resp.text = "fake-jwt-token"

    list_resp = MagicMock()
    list_resp.raise_for_status = MagicMock()
    list_resp.json.return_value = tree

    pdf_resp = MagicMock()
    pdf_resp.raise_for_status = MagicMock()
    pdf_resp.content = pdf

    ocr_resp = MagicMock()
    ocr_resp.raise_for_status = MagicMock()
    ocr_resp.json.return_value = {"response": "Transcribed text"}

    # post → login or ollama; get → list or pdf download
    async def fake_post(url, **kwargs):
        if "login" in url:
            return login_resp
        return ocr_resp

    async def fake_get(url, **kwargs):
        if url.endswith("/documents"):
            return list_resp
        return pdf_resp

    class FakeClient:
        async def __aenter__(self):
            return self

        async def __aexit__(self, *_):
            pass

        post = AsyncMock(side_effect=fake_post)
        get = AsyncMock(side_effect=fake_get)

    return patch("httpx.AsyncClient", return_value=FakeClient())


@pytest.mark.asyncio
async def test_sync_processes_new_document(tmp_vault, fake_pdf_images):
    import app as bridge

    tree = make_tree([make_doc("doc-1", "My Meeting")])
    with fake_http(tree):
        await bridge.run_sync_and_ocr_job()

    md_file = bridge.NOTES_DIR / "My_Meeting.md"
    assert md_file.exists()
    content = md_file.read_text()
    assert "Transcribed text" in content
    assert "pages: 2" in content


@pytest.mark.asyncio
async def test_sync_mirrors_folder_structure(tmp_vault, fake_pdf_images):
    import app as bridge

    tree = make_tree([
        make_folder("Work", [
            make_folder("Q1", [
                make_doc("doc-1", "Standup"),
            ]),
        ]),
    ])
    with fake_http(tree):
        await bridge.run_sync_and_ocr_job()

    assert (bridge.NOTES_DIR / "Work" / "Q1" / "Standup.md").exists()


@pytest.mark.asyncio
async def test_sync_reprocesses_updated_document(tmp_vault, fake_pdf_images):
    import app as bridge

    bridge.STATE_FILE.write_text(json.dumps({
        "doc-1": {"title": "Note", "processed_at": "...", "folder_path": "", "last_modified": "2026-01-01T00:00:00Z"},
    }))
    doc = {**make_doc("doc-1", "Note"), "lastModified": "2026-06-01T00:00:00Z"}
    tree = make_tree([doc])
    with fake_http(tree):
        await bridge.run_sync_and_ocr_job()

    assert any(bridge.NOTES_DIR.glob("*.md"))


@pytest.mark.asyncio
async def test_sync_skips_already_processed(tmp_vault, fake_pdf_images):
    import app as bridge

    bridge.STATE_FILE.write_text(
        json.dumps({"doc-1": {"title": "Note", "processed_at": "...", "folder_path": "", "last_modified": "2026-06-01T00:00:00Z"}})
    )
    tree = make_tree([make_doc("doc-1", "Note")])
    with fake_http(tree):
        await bridge.run_sync_and_ocr_job()

    assert not any(bridge.NOTES_DIR.glob("*.md"))


@pytest.mark.asyncio
async def test_sync_saves_state_on_success(tmp_vault, fake_pdf_images):
    import app as bridge

    tree = make_tree([make_doc("doc-1", "My Note")])
    with fake_http(tree):
        await bridge.run_sync_and_ocr_job()

    state = json.loads(bridge.STATE_FILE.read_text())
    assert "doc-1" in state
    assert state["doc-1"]["title"] == "My Note"


@pytest.mark.asyncio
async def test_sync_leaves_unprocessed_on_failure(tmp_vault):
    import app as bridge

    tree = make_tree([make_doc("doc-1", "Broken Note")])

    with patch("app.pdf_to_images", side_effect=Exception("PDF parse error")):
        with fake_http(tree):
            await bridge.run_sync_and_ocr_job()

    state = bridge.load_state()
    assert "doc-1" not in state


@pytest.mark.asyncio
async def test_sync_no_new_docs(tmp_vault, fake_pdf_images):
    import app as bridge

    tree = make_tree([])
    with fake_http(tree):
        await bridge.run_sync_and_ocr_job()

    assert not any(bridge.NOTES_DIR.glob("*.md"))
