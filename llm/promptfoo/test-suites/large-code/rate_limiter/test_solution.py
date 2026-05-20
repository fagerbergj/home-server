"""Behavioral tests for an async rate-limited HTTP client.
Solution must expose an `async def fetch(urls: list[str], rate: int) -> list[dict]`
that fetches all URLs with at most `rate` requests per second. Each returned
dict has keys 'url', 'status', and either 'body' or 'error'. Retries with
exponential backoff on transient failures."""
import asyncio
import time
import pytest
from solution import fetch


def _run(coro):
    return asyncio.run(coro)


def test_basic_fetch():
    # Use httpbin or a known endpoint; substitute with a stable test URL.
    urls = ["https://httpbin.org/status/200"]
    results = _run(fetch(urls, rate=2))
    assert len(results) == 1
    assert results[0]["url"] == urls[0]
    assert results[0]["status"] == 200


def test_returns_one_result_per_url():
    urls = [
        "https://httpbin.org/status/200",
        "https://httpbin.org/status/200",
        "https://httpbin.org/status/200",
    ]
    results = _run(fetch(urls, rate=10))
    assert len(results) == 3


def test_rate_limit_enforced():
    # 6 requests at rate=2 should take at least ~2 seconds (3 windows)
    urls = ["https://httpbin.org/status/200"] * 6
    start = time.time()
    _run(fetch(urls, rate=2))
    elapsed = time.time() - start
    # Allow 30% slack; rate-limiting should give >= ~2s
    assert elapsed >= 1.5, f"expected rate limiting, took only {elapsed:.2f}s"


def test_handles_error_status():
    urls = ["https://httpbin.org/status/500"]
    results = _run(fetch(urls, rate=2))
    assert len(results) == 1
    # Either status 500 returned or an error key after retries gave up
    assert results[0]["status"] == 500 or "error" in results[0]
