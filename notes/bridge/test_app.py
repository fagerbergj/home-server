import io
import json
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi.testclient import TestClient


@pytest.fixture(autouse=True)
def tmp_vault(tmp_path, monkeypatch):
    import app as bridge
    monkeypatch.setattr(bridge, "VAULT_PATH", tmp_path)
    monkeypatch.setattr(bridge, "NOTES_DIR", tmp_path / "remarkable")
    (tmp_path / "remarkable").mkdir(parents=True)
    return tmp_path


@pytest.fixture
def client(tmp_vault):
    import app as bridge
    with TestClient(bridge.app) as c:
        yield c


@pytest.fixture
def mock_ocr():
    fake = MagicMock()
    fake.is_error = False
    fake.raise_for_status = MagicMock()
    fake.json.return_value = {"response": "Transcribed text"}
    with patch("httpx.AsyncClient.post", new_callable=AsyncMock, return_value=fake):
        yield fake


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


def test_webhook_writes_md(client, tmp_vault, mock_ocr):
    resp = client.post(
        "/webhook",
        files={"attachment": ("sheet.png", io.BytesIO(b"FAKEPNG"), "image/png")},
        data={"data": json.dumps({"title": "My Note", "parent": ""})},
    )
    assert resp.status_code == 200
    assert resp.json()["title"] == "My Note"

    import app as bridge
    md = (bridge.NOTES_DIR / "My_Note.md").read_text()
    assert "Transcribed text" in md
    assert "pages: 1" in md


def test_webhook_mirrors_folder(client, tmp_vault, mock_ocr):
    resp = client.post(
        "/webhook",
        files={"attachment": ("sheet.png", io.BytesIO(b"FAKEPNG"), "image/png")},
        data={"data": json.dumps({"title": "Standup", "parent": "Work/Q1"})},
    )
    assert resp.status_code == 200

    import app as bridge
    assert (bridge.NOTES_DIR / "Work" / "Q1" / "Standup.md").exists()


# ── sanitize ──────────────────────────────────────────────────────────────────


def test_sanitize_spaces():
    from app import sanitize
    assert sanitize("My Note") == "My_Note"


def test_sanitize_path_traversal():
    from app import sanitize
    assert ".." not in sanitize("../../etc/passwd")


def test_sanitize_empty():
    from app import sanitize
    assert sanitize("!!!") == "untitled"
