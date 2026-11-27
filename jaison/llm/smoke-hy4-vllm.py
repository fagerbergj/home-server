#!/usr/bin/env python3
"""Smoke test hy4-vllm (:9989): coding/reasoning quality, tool calling, vision, DFly metrics."""
import base64
import json
import struct
import sys
import time
import urllib.request
import zlib

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 9989
BASE = f"http://127.0.0.1:{PORT}"
MODEL = "hy4-vllm"


def post_chat(body: dict) -> tuple[dict, float]:
    t0 = time.time()
    req = urllib.request.Request(
        f"{BASE}/v1/chat/completions",
        data=json.dumps(body).encode(),
        headers={"content-type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=300) as r:
        return json.loads(r.read()), time.time() - t0


def make_red_png(w: int = 64, h: int = 64) -> str:
    """Minimal valid RGB PNG (solid bright red) — no PIL dependency."""
    raw = b"".join(b"\x00" + b"\xff\x00\x00" * w for _ in range(h))
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
    return base64.b64encode(png).decode()


# 1. Coding + reasoning
print("=== 1/3 Coding + reasoning ===")
resp, dt = post_chat({
    "model": MODEL,
    "messages": [{"role": "user", "content": "Write a concise Python function to merge overlapping intervals [(start, end), ...], and explain its time complexity in one sentence."}],
    "max_tokens": 512,
    "temperature": 0.0,
})
msg = resp["choices"][0]["message"]
u = resp.get("usage", {})
ct = u.get("completion_tokens", 0)
print(f"tokens: prompt={u.get('prompt_tokens')} completion={ct} | wall={dt:.2f}s ({ct/dt:.1f} tok/s)")
if msg.get("reasoning_content") or msg.get("reasoning"):
    rc = msg.get("reasoning_content") or msg.get("reasoning")
    print(f"reasoning ({len(rc)} chars): {rc[:200]!r}...")
print("content:\n" + (msg.get("content") or "")[:600])

# 2. Tool calling
print("\n=== 2/3 Tool calling ===")
resp2, dt2 = post_chat({
    "model": MODEL,
    "messages": [{"role": "user", "content": "What is the current disk usage on /mnt/cache?"}],
    "tools": [{
        "type": "function",
        "function": {
            "name": "run_bash",
            "description": "Execute a read-only shell command.",
            "parameters": {
                "type": "object",
                "properties": {"cmd": {"type": "string"}},
                "required": ["cmd"],
            },
        },
    }],
    "max_tokens": 256,
    "temperature": 0.0,
})
msg2 = resp2["choices"][0]["message"]
print(f"wall={dt2:.2f}s | tool_calls={json.dumps(msg2.get('tool_calls'))} | content={(msg2.get('content') or '')[:160]!r}")

# 3. Vision
print("\n=== 3/3 Vision (64x64 solid red PNG) ===")
try:
    resp3, dt3 = post_chat({
        "model": MODEL,
        "messages": [{
            "role": "user",
            "content": [
                {"type": "text", "text": "What single color is this image? Answer in one word."},
                {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{make_red_png()}"}},
            ],
        }],
        "max_tokens": 128,
        "temperature": 0.0,
    })
    msg3 = resp3["choices"][0]["message"]
    print(f"wall={dt3:.2f}s | content={(msg3.get('content') or '')[:200]!r}")
except Exception as e:
    print(f"VISION ERROR: {e}")

# 4. DFly metrics
print("\n=== DFly spec metrics (:9989/metrics) ===")
try:
    m = urllib.request.urlopen(f"{BASE}/metrics", timeout=10).read().decode()
    for line in m.splitlines():
        if "spec_decode" in line and not line.startswith("#"):
            print(" ", line)
except Exception as e:
    print(f"METRICS ERROR: {e}")
