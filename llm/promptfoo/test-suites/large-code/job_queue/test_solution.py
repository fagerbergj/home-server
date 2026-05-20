"""Behavioral tests for a SQLite-backed job queue.
Solution must expose a class `JobQueue(db_path)` with:
  - enqueue(payload: dict) -> job_id
  - dequeue() -> (job_id, payload) or None
  - complete(job_id) -> None
  - fail(job_id) -> None  (increments retry; moves to DLQ after max retries)
  - dlq() -> list of failed payloads
  - MAX_RETRIES class attribute (or instance attribute)"""
import pytest
import tempfile
import os
from solution import JobQueue


@pytest.fixture
def queue():
    fd, path = tempfile.mkstemp(suffix=".db")
    os.close(fd)
    q = JobQueue(path)
    yield q
    os.unlink(path)


def test_enqueue_and_dequeue(queue):
    job_id = queue.enqueue({"task": "send_email", "to": "test@example.com"})
    assert job_id is not None
    result = queue.dequeue()
    assert result is not None
    rid, payload = result
    assert payload["task"] == "send_email"


def test_dequeue_empty(queue):
    assert queue.dequeue() is None


def test_fifo_ordering(queue):
    queue.enqueue({"n": 1})
    queue.enqueue({"n": 2})
    queue.enqueue({"n": 3})
    _, p1 = queue.dequeue()
    _, p2 = queue.dequeue()
    _, p3 = queue.dequeue()
    assert p1["n"] == 1
    assert p2["n"] == 2
    assert p3["n"] == 3


def test_complete_removes_job(queue):
    job_id = queue.enqueue({"x": 1})
    rid, _ = queue.dequeue()
    queue.complete(rid)
    # After complete, queue should be empty
    assert queue.dequeue() is None


def test_fail_with_retries(queue):
    job_id = queue.enqueue({"x": 1})
    # First fail — should still be retryable
    rid, _ = queue.dequeue()
    queue.fail(rid)
    # Should be requeued
    result = queue.dequeue()
    assert result is not None


def test_max_retries_moves_to_dlq(queue):
    queue.enqueue({"task": "fail_me"})
    max_retries = getattr(queue, "MAX_RETRIES", 3)
    # Fail max_retries + 1 times
    for _ in range(max_retries + 1):
        result = queue.dequeue()
        if result is None:
            break
        rid, _ = result
        queue.fail(rid)
    dlq = queue.dlq()
    assert any(p.get("task") == "fail_me" for p in dlq)
