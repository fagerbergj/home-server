#!/usr/bin/env python3
"""
llmcalc — interactive Ollama model fit + tok/s estimator.

Usage:
  ./llmcalc.py                          # prompts for a blob URL, then fields
  ./llmcalc.py <ollama-blob-url>        # auto-fetch + fill what it can
  ./llmcalc.py --hardware               # re-run hardware setup
"""
from __future__ import annotations

import argparse
import json
import os
import re
import struct
import sys
import urllib.request
from dataclasses import dataclass, asdict
from html.parser import HTMLParser
from pathlib import Path

CONFIG_PATH = Path(os.path.expanduser("~/.config/llmcalc.json"))

# Realistic bandwidth derate vs. theoretical peak. Calibrated against measured
# Ollama tok/s on RTX 3090 across qwen2.5:7b, devstral-small-2:24b, gpt-oss:20b.
DERATE = 0.82
# Fraction of VRAM that's actually usable for model+KV. Ollama reserves the rest
# for compute graph, CUDA scratch, OS, etc. Calibrated empirically.
USABLE_VRAM_FRAC = 0.80
KV_BYTES = {"f16": 2.0, "q8_0": 1.0, "q4_0": 0.5}

# Context ladder — powers of 2 with 1.5x half-steps for granularity, up to 1M
CTX_LADDER = [
    2048, 3072, 4096, 6144, 8192, 12288, 16384, 24576, 32768, 49152,
    65536, 98304, 131072, 196608, 262144, 393216, 524288, 786432, 1048576,
]
MAX_ROWS = 12
MIN_USABLE_TOK_S = 15      # ✓ at or above this — recommended
WARN_TOK_S = 10            # ⚠ between WARN_TOK_S and MIN_USABLE_TOK_S — workable but slow
SHOW_UNUSABLE_ROWS = 2     # keep this many below the warn threshold to show the cliff
MIN_TOTAL_ROWS = 5         # always show at least this many rows, even if unusable


# ──────────────────────────────────────────────────────────────────────────────
# Hardware profile
# ──────────────────────────────────────────────────────────────────────────────
@dataclass
class Hardware:
    gpu_name: str
    vram_gib: float
    vram_bw_gbs: float        # GB/s
    ram_gib: float
    ram_bw_gbs: float
    swap_gib: float
    swap_bw_gbs: float        # NVMe ~3.5 (gen3) / 7 (gen4)
    kv_cache_type: str = "q8_0"   # matches OLLAMA_KV_CACHE_TYPE env var


def prompt(msg: str, default: str | None = None, cast=str):
    suffix = f" [{default}]" if default is not None else ""
    while True:
        raw = input(f"{msg}{suffix}: ").strip()
        if not raw and default is not None:
            raw = str(default)
        if not raw:
            continue
        try:
            return cast(raw)
        except ValueError:
            print(f"  ! couldn't parse '{raw}' as {cast.__name__}")


def setup_hardware() -> Hardware:
    print("\n── Hardware profile (saved to ~/.config/llmcalc.json) ──")
    print("Tip: VRAM bandwidth — RTX 3090: 936, 4090: 1008, 4070: 504")
    print("Tip: DDR4-2400 quad-channel ≈ 76.8 peak (use ~55), dual ≈ 38.4 (use ~28)")
    print("Tip: NVMe Gen3 ≈ 3.5, Gen4 ≈ 7")
    hw = Hardware(
        gpu_name=prompt("GPU name", "RTX 3090"),
        vram_gib=prompt("VRAM (GiB)", "24", float),
        vram_bw_gbs=prompt("VRAM bandwidth (GB/s, theoretical peak)", "936", float),
        ram_gib=prompt("System RAM (GiB)", "64", float),
        ram_bw_gbs=prompt("RAM bandwidth (GB/s, theoretical peak)", "55", float),
        swap_gib=prompt("Swap (GiB, 0 if none)", "0", float),
        swap_bw_gbs=prompt("Swap/NVMe bandwidth (GB/s)", "3.5", float),
        kv_cache_type=prompt("KV cache type — match OLLAMA_KV_CACHE_TYPE (f16/q8_0/q4_0)", "q8_0"),
    )
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(json.dumps(asdict(hw), indent=2))
    print(f"Saved → {CONFIG_PATH}\n")
    return hw


def load_hardware() -> Hardware:
    if not CONFIG_PATH.exists():
        return setup_hardware()
    return Hardware(**json.loads(CONFIG_PATH.read_text()))


# ──────────────────────────────────────────────────────────────────────────────
# Blob page fetch + parse
# ──────────────────────────────────────────────────────────────────────────────
class BlobParser(HTMLParser):
    """
    Ollama blob pages render GGUF metadata as a key/value layout. We don't depend
    on the exact tag structure — we just collect all visible text and extract
    `key = value` pairs and `key value` neighbours via regex on the flattened text.
    """
    def __init__(self):
        super().__init__()
        self.chunks: list[str] = []
        self._skip = 0

    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style"):
            self._skip += 1

    def handle_endtag(self, tag):
        if tag in ("script", "style") and self._skip:
            self._skip -= 1

    def handle_data(self, data):
        if self._skip:
            return
        s = data.strip()
        if s:
            self.chunks.append(s)


# ──────────────────────────────────────────────────────────────────────────────
# GGUF header parser — used to recover the full head_count_kv array that the
# Ollama blob page truncates to "..." for hybrid SSM/attention models.
#
# Strategy: parse the model name + short blob hash from the page URL, look up
# the manifest on registry.ollama.ai, then HTTP Range-request the first ~512KB
# of the model blob and walk the GGUF metadata KV section.
# ──────────────────────────────────────────────────────────────────────────────
GGUF_TYPES = {
    0: ("B", 1), 1: ("b", 1), 2: ("H", 2), 3: ("h", 2),
    4: ("I", 4), 5: ("i", 4), 6: ("f", 4), 7: ("?", 1),
    10: ("Q", 8), 11: ("q", 8), 12: ("d", 8),
}  # 8=string, 9=array — handled separately


def _read_str(buf: bytes, off: int):
    n = struct.unpack_from("<Q", buf, off)[0]
    off += 8
    return buf[off:off + n].decode("utf-8", errors="replace"), off + n


def _skip_value(buf: bytes, off: int, vtype: int) -> int:
    """Advance past a value without allocating it (used for huge vocab arrays)."""
    if vtype in GGUF_TYPES:
        return off + GGUF_TYPES[vtype][1]
    if vtype == 8:
        n = struct.unpack_from("<Q", buf, off)[0]
        return off + 8 + n
    if vtype == 9:
        et = struct.unpack_from("<I", buf, off)[0]; off += 4
        n  = struct.unpack_from("<Q", buf, off)[0]; off += 8
        if et in GGUF_TYPES:
            return off + n * GGUF_TYPES[et][1]
        for _ in range(n):
            off = _skip_value(buf, off, et)
        return off
    raise ValueError(f"unknown gguf type {vtype}")


def _read_value(buf: bytes, off: int, vtype: int, store: bool = True):
    if vtype in GGUF_TYPES:
        fmt, sz = GGUF_TYPES[vtype]
        return struct.unpack_from("<" + fmt, buf, off)[0], off + sz
    if vtype == 8:
        return _read_str(buf, off)
    if vtype == 9:
        et = struct.unpack_from("<I", buf, off)[0]; off += 4
        n  = struct.unpack_from("<Q", buf, off)[0]; off += 8
        # If caller doesn't want the contents (e.g. tokenizer vocab), skip them
        if not store:
            for _ in range(n):
                off = _skip_value(buf, off, et)
            return None, off
        items = []
        for _ in range(n):
            v, off = _read_value(buf, off, et)
            items.append(v)
        return items, off
    raise ValueError(f"unknown gguf type {vtype}")


SKIP_KEY_PREFIXES = ("tokenizer.",)  # vocab/merges arrays — huge, never needed here


def _parse_gguf_kv(buf: bytes) -> dict:
    if buf[:4] != b"GGUF":
        raise ValueError("not a GGUF blob")
    _version = struct.unpack_from("<I", buf, 4)[0]
    off = 8
    _tensor_count = struct.unpack_from("<Q", buf, off)[0]; off += 8
    kv_count      = struct.unpack_from("<Q", buf, off)[0]; off += 8
    out = {}
    for _ in range(kv_count):
        key, off = _read_str(buf, off)
        vtype = struct.unpack_from("<I", buf, off)[0]; off += 4
        store = not any(key.startswith(p) for p in SKIP_KEY_PREFIXES)
        val, off = _read_value(buf, off, vtype, store=store)
        if store:
            out[key] = val
    return out


def fetch_gguf_metadata(model_url: str) -> dict | None:
    """Best-effort: pull GGUF metadata for the model behind an ollama.com blob URL.
    Returns the parsed KV dict, or None on any failure (network, parse, mismatch)."""
    # Match either /library/<name> or /<user>/<name>
    m = re.search(r"ollama\.com/((?:library|[^/]+))/([^/]+)/blobs/([a-f0-9]+)", model_url)
    if not m:
        return None
    namespace, name, short_hash = m.group(1), m.group(2), m.group(3)
    repo, _, tag = name.partition(":")
    tag = tag or "latest"
    registry_path = f"{namespace}/{repo}"
    try:
        man_url = f"https://registry.ollama.ai/v2/{registry_path}/manifests/{tag}"
        man = json.loads(urllib.request.urlopen(
            urllib.request.Request(man_url, headers={
                "Accept": "application/vnd.docker.distribution.manifest.v2+json"}),
            timeout=10).read())
        layer = next((l for l in man["layers"]
                      if l["mediaType"] == "application/vnd.ollama.image.model"
                      and short_hash in l["digest"]), None)
        if not layer:
            return None
        blob_url = f"https://registry.ollama.ai/v2/{registry_path}/blobs/{layer['digest']}"
        req = urllib.request.Request(blob_url, headers={"Range": "bytes=0-33554431"})  # 32 MiB
        chunk = urllib.request.urlopen(req, timeout=60).read()
        return _parse_gguf_kv(chunk)
    except Exception:
        return None


def fetch_blob(url: str) -> dict:
    print(f"Fetching {url} ...")
    req = urllib.request.Request(url, headers={"User-Agent": "llmcalc/1.0"})
    with urllib.request.urlopen(req, timeout=15) as r:
        html = r.read().decode("utf-8", errors="replace")
    parser = BlobParser()
    parser.feed(html)
    text = "\n".join(parser.chunks)

    out: dict = {}

    # Friendly name from URL: /library/<name>:<tag>/blobs/... or /<user>/<name>:<tag>/blobs/...
    m = re.search(r"/(?:library|[^/]+)/([^/]+)/blobs/", url)
    if m:
        out["name"] = m.group(1)

    # Model file size — try the raw GGUF size shown on the page
    m = re.search(r"([\d.]+)\s*GB\b", text)
    if m:
        out["file_gib"] = float(m.group(1))  # Ollama shows GB, treat as ~GiB

    # general.file_type → quant bits (handles Q4_K_M, MXFP4, BF16, F16, Q8_0, ...)
    m = re.search(r"general\.file_type[^\n]*\n\s*([A-Z0-9_]+)", text)
    if m:
        try:
            out["quant_bits"] = parse_quant(m.group(1))
        except ValueError:
            pass

    # Generic <arch>.<field> = <int> extraction
    field_re = re.compile(
        r"([a-z0-9_]+\.(?:embedding_length|block_count|"
        r"attention\.head_count_kv|attention\.head_count|"
        r"attention\.key_length|attention\.value_length|"
        r"context_length|expert_count|expert_used_count|"
        r"ssm\.state_size|ssm\.inner_size))[^\d\[-]*([\d]+)",
        re.IGNORECASE,
    )
    for key, val in field_re.findall(text):
        k = key.lower()
        if k.endswith(".embedding_length") and "embedding" not in out:
            out["embedding"] = int(val)
        elif k.endswith(".block_count") and "blocks" not in out:
            out["blocks"] = int(val)
        elif k.endswith(".attention.head_count") and not k.endswith("_kv") and "_head_count" not in out:
            out["_head_count"] = int(val)
        elif k.endswith(".attention.head_count_kv") and "kv_heads" not in out:
            out["kv_heads"] = int(val)
        elif k.endswith(".attention.key_length") and "kv_len" not in out:
            out["kv_len"] = int(val)
        elif k.endswith(".context_length") and "ctx_max" not in out:
            out["ctx_max"] = int(val)
        elif k.endswith(".expert_count") and "experts" not in out:
            out["experts"] = int(val)
        elif k.endswith(".expert_used_count") and "experts_used" not in out:
            out["experts_used"] = int(val)
        elif k.endswith(".ssm.state_size") and "ssm_state_size" not in out:
            out["ssm_state_size"] = int(val)
        elif k.endswith(".ssm.inner_size") and "ssm_inner_size" not in out:
            out["ssm_inner_size"] = int(val)

    # head_count_kv as array — could be uniform (e.g. gemma "[16, 16, ...]")
    # or mixed with zeros indicating hybrid SSM (e.g. qwen3.6 "[0, 0, 0, 4, 0, ...]")
    arr_match = re.search(
        r"head_count_kv[^\[]{0,200}\[([^\]]+)\]", text
    )
    if arr_match:
        nums = [int(n) for n in re.findall(r"\d+", arr_match.group(1))]
        nonzero = [n for n in nums if n > 0]
        if nonzero:
            # Always take first nonzero as kv_heads (correct for both uniform & hybrid)
            out["kv_heads"] = nonzero[0]
            # Mixed array (some zeros) → hybrid SSM
            if 0 in nums:
                out["arch"] = "ssm"
                out["_kv_array_truncated"] = "..." in arr_match.group(1)

    # Also flag SSM if ssm.* fields exist (covers pure SSM without mixed array)
    if re.search(r"\.ssm\.(state_size|conv_kernel|inner_size)", text):
        out["arch"] = "ssm"

    # Compute kv_len from embedding_length / head_count when not explicitly listed
    # (typical for Llama/Mistral/Mixtral; Gemma overrides with its own key_length).
    if "kv_len" not in out and "_head_count" in out and "embedding" in out:
        if out["_head_count"] > 0 and out["embedding"] % out["_head_count"] == 0:
            out["kv_len"] = out["embedding"] // out["_head_count"]
    out.pop("_head_count", None)

    # For hybrid SSM, the displayed head_count_kv array is usually truncated (and
    # may even start with all zeros, hiding the attention blocks entirely). Always
    # fetch the GGUF header to recover the full array when arch=ssm.
    if out.get("arch") == "ssm" and "attention_blocks" not in out:
        print("  Hybrid SSM detected — fetching GGUF header for full attention array...")
        meta = fetch_gguf_metadata(url)
        if meta:
            arr_key = next((k for k in meta if k.endswith(".attention.head_count_kv")), None)
            if arr_key and isinstance(meta[arr_key], list):
                arr = meta[arr_key]
                nonzero = [n for n in arr if n > 0]
                out["attention_blocks"] = len(nonzero)
                if nonzero:
                    out["kv_heads"] = nonzero[0]
                print(f"  ✓ Parsed {len(arr)} blocks → {len(nonzero)} attention, "
                      f"{len(arr) - len(nonzero)} SSM (kv_heads={nonzero[0] if nonzero else 0})")
            else:
                print("  ! head_count_kv not found in GGUF metadata.")
        else:
            print("  ! GGUF fetch failed — will prompt for attention block count.")
        out.pop("_kv_array_truncated", None)

    return out


# ──────────────────────────────────────────────────────────────────────────────
# Model spec collection
# ──────────────────────────────────────────────────────────────────────────────
@dataclass
class Model:
    file_gib: float
    quant_bits: int
    embedding: int
    blocks: int
    kv_heads: int
    kv_len: int
    arch: str = "transformer"  # or "ssm" (hybrid)
    name: str = ""
    ctx_max: int = 0           # model's declared max context (0 = unknown)
    attention_blocks: int = 0  # for arch=ssm: how many blocks have attention (rest are SSM)
    ssm_state_size: int = 0    # SSM recurrent state dim per layer
    ssm_inner_size: int = 0    # SSM inner projection dim per layer
    experts: int = 0           # MoE total experts (0 = dense model)
    experts_used: int = 0      # MoE active experts per token

# Rough fraction of weights that are NOT expert (attention, embeddings, layer norms,
# router). Calibrated against gpt-oss:20b's flat 154 t/s across all contexts.
MOE_SHARED_FRAC = 0.30


def parse_quant(s: str) -> int:
    """Accept Q4_K_M / MXFP4 / BF16 / F16 / Q8_0 / 4 etc. → integer bits."""
    s = s.strip().upper()
    m = re.search(r"\d+", s)
    if not m:
        raise ValueError(f"can't extract bit count from {s!r}")
    return int(m.group(0))


HINTS = {
    "file_gib":    ('Look for "Model size" near the top of the page (e.g. "20 GB"). Enter GiB.', float),
    "quant_bits":  ('Find "general.file_type" — e.g. "Q4_K_M", "MXFP4", "BF16", "F16". Paste it as-is or just the number.', parse_quant),
    "embedding":   ('Find "<arch>.embedding_length" (e.g. "qwen3.embedding_length").', int),
    "blocks":      ('Find "<arch>.block_count".', int),
    "kv_heads":    ('Find "<arch>.attention.head_count_kv". 0 if not shown (will use embedding as proxy).', int),
    "kv_len":      ('Find "<arch>.attention.key_length". Default 128 if not shown.', int),
    "attention_blocks": (
        'Hybrid SSM: only some of the blocks use attention (the rest are SSM with\n'
        '  fixed-size state). The "attention.head_count_kv" field on the page is an\n'
        '  array, e.g. [0, 0, 0, 4, 0, 0, 0, 4, ...] — but Ollama truncates it.\n'
        '  Couldn\'t parse it from the GGUF either. Best to guess based on the model:\n'
        '  most hybrids use 1-in-4 to 1-in-8 attention blocks.\n'
        '  Enter total attention block count (0 = skip, gives optimistic estimate)',
        int,
    ),
}


def collect_model(prefilled: dict) -> Model:
    print("\n── Model spec ──")
    if prefilled:
        print(f"Auto-detected: {sorted(k for k in prefilled if k != 'name')}\n")
    if "name" in prefilled:
        print(f"  ✓ name: {prefilled['name']} (auto)")
        name = prefilled["name"]
    else:
        name = prompt("Friendly name for this model", "model")

    def get(field, default=None):
        hint, cast = HINTS[field]
        if field in prefilled:
            print(f"  ✓ {field}: {prefilled[field]} (auto)")
            return prefilled[field]
        print(f"  {hint}")
        return prompt(f"  {field}", default, cast)

    arch = prefilled.get("arch", "transformer")
    if arch == "ssm":
        truncated = prefilled.get("_kv_array_truncated")
        suffix = " — array was truncated on the page" if truncated else ""
        print(f"  ✓ arch: ssm (hybrid SSM/attention detected{suffix})")

    file_gib   = get("file_gib")
    quant_bits = get("quant_bits")
    embedding  = get("embedding")
    blocks     = get("blocks")
    kv_heads   = get("kv_heads", "0")
    kv_len     = get("kv_len", "128")

    # For hybrid SSM, ask for attention block count (KV grows only on those)
    attention_blocks = 0
    if arch == "ssm":
        if "attention_blocks" in prefilled:
            attention_blocks = prefilled["attention_blocks"]
            print(f"  ✓ attention_blocks: {attention_blocks} (auto from GGUF)")
        else:
            default_att = max(1, blocks // 8)
            attention_blocks = get("attention_blocks", str(default_att))

    return Model(
        name=name,
        file_gib=file_gib, quant_bits=quant_bits, embedding=embedding,
        blocks=blocks, kv_heads=kv_heads, kv_len=kv_len, arch=arch,
        ctx_max=int(prefilled.get("ctx_max", 0)),
        attention_blocks=attention_blocks,
        ssm_state_size=int(prefilled.get("ssm_state_size", 0)),
        ssm_inner_size=int(prefilled.get("ssm_inner_size", 0)),
        experts=int(prefilled.get("experts", 0)),
        experts_used=int(prefilled.get("experts_used", 0)),
    )


# ──────────────────────────────────────────────────────────────────────────────
# Math
# ──────────────────────────────────────────────────────────────────────────────
def kv_cache_gib(m: Model, hw: Hardware, ctx: int) -> float:
    """KV cache (grows with context) + fixed SSM recurrent state (constant)."""
    bpe = KV_BYTES[hw.kv_cache_type]
    heads = m.kv_heads if m.kv_heads > 0 else m.embedding

    if m.arch == "ssm":
        # Only attention_blocks contribute to growing KV cache; SSM blocks have fixed state.
        att_blocks = m.attention_blocks
        ssm_blocks = max(0, m.blocks - att_blocks)
        kv = 2 * att_blocks * ctx * heads * m.kv_len * bpe / (1024 ** 3)
        # Fixed SSM state: ~inner_size × state_size × 2 bytes (fp16) per SSM block
        if m.ssm_state_size and m.ssm_inner_size:
            ssm_state = ssm_blocks * m.ssm_inner_size * m.ssm_state_size * 2 / (1024 ** 3)
        else:
            ssm_state = 0.0
        return kv + ssm_state

    return 2 * m.blocks * ctx * heads * m.kv_len * bpe / (1024 ** 3)


def plan(m: Model, hw: Hardware, ctx: int) -> dict:
    """Greedy layer placement: VRAM → RAM → swap. KV cache rides with its layer."""
    vram_avail = hw.vram_gib * USABLE_VRAM_FRAC
    weight_per_layer = m.file_gib / m.blocks
    kv_per_layer = kv_cache_gib(m, hw, ctx) / max(m.blocks, 1)
    per_layer = weight_per_layer + kv_per_layer

    layers_vram = min(m.blocks, int(vram_avail // per_layer)) if per_layer > 0 else m.blocks
    rem = m.blocks - layers_vram
    layers_ram = min(rem, int(hw.ram_gib // per_layer)) if per_layer > 0 else 0
    rem -= layers_ram
    layers_swap = min(rem, int(hw.swap_gib // per_layer)) if per_layer > 0 and hw.swap_gib > 0 else 0
    layers_unfit = rem - layers_swap

    vram_used = layers_vram * per_layer + (hw.vram_gib - vram_avail)
    ram_used  = layers_ram  * per_layer
    swap_used = layers_swap * per_layer

    # tok/s: time per token = sum over tiers of bytes_read / bandwidth.
    # Dense: every weight is read per token. MoE: shared weights + active experts only.
    # KV cache is excluded: with flash attention it's tiled and contributes negligibly
    # to the per-token bandwidth budget (verified empirically — flat tok/s across ctx).
    if m.experts > 0 and m.experts_used > 0:
        active_frac = MOE_SHARED_FRAC + (1 - MOE_SHARED_FRAC) * (m.experts_used / m.experts)
        weight_bytes_gib = m.file_gib * active_frac
    else:
        weight_bytes_gib = m.file_gib
    bytes_per_token_gib = weight_bytes_gib
    if layers_unfit > 0 or bytes_per_token_gib == 0:
        tok_s = 0.0
    else:
        total_layers = m.blocks
        f_v = layers_vram / total_layers
        f_r = layers_ram  / total_layers
        f_s = layers_swap / total_layers
        t_per_token = bytes_per_token_gib * (
            f_v / hw.vram_bw_gbs +
            f_r / hw.ram_bw_gbs +
            (f_s / hw.swap_bw_gbs if hw.swap_bw_gbs > 0 else 0)
        )
        tok_s = DERATE / t_per_token if t_per_token > 0 else 0.0

    return {
        "ctx": ctx,
        "vram": vram_used, "ram": ram_used, "swap": swap_used,
        "layers_vram": layers_vram, "layers_ram": layers_ram,
        "layers_swap": layers_swap, "layers_unfit": layers_unfit,
        "tok_s": tok_s,
    }


def fmt_row(p: dict, blocks: int, ctx_max: int = 0) -> str:
    # Icon reflects usability (tok/s), not placement — RAM spill is fine if it's still fast.
    if p["layers_unfit"] > 0 or p["tok_s"] < WARN_TOK_S:
        icon = "✗"
    elif p["tok_s"] < MIN_USABLE_TOK_S:
        icon = "⚠"
    else:
        icon = "✓"

    if p["layers_unfit"] > 0:
        detail = f"{p['layers_unfit']} layers don't fit"
    elif p["layers_swap"] > 0:
        detail = f"{p['layers_swap']}/{blocks} layers in swap"
    elif p["layers_ram"] > 0:
        detail = f"{p['layers_ram']}/{blocks} layers in RAM"
    else:
        detail = "100% GPU"

    if ctx_max and p["ctx"] == ctx_max:
        detail += " (model max)"

    tok = f"{p['tok_s']:.0f}" if p["tok_s"] > 0 else "—"
    return (f"  {p['ctx']:>7}  "
            f"{p['vram']:>5.1f}  {p['ram']:>5.1f}  {p['swap']:>5.1f}  "
            f"{tok:>8}   {icon} {detail}")


def report(m: Model, hw: Hardware):
    print(f"\n────────────────────────────────────────────────────")
    arch_note = ""
    if m.arch == "ssm":
        arch_note += f", hybrid SSM ({m.attention_blocks}/{m.blocks} attention blocks)"
    if m.experts > 0:
        arch_note += f", MoE ({m.experts_used}/{m.experts} experts active)"
    print(f"  {m.name}  ({m.file_gib:.1f} GiB, Q{m.quant_bits}, "
          f"{m.blocks} blocks, KV={m.kv_heads or 'embed'}, kv_type={hw.kv_cache_type}{arch_note})")
    print(f"  Hardware: {hw.gpu_name} {hw.vram_gib:.0f}GiB @ {hw.vram_bw_gbs:.0f}GB/s | "
          f"RAM {hw.ram_gib:.0f}GiB @ {hw.ram_bw_gbs:.0f}GB/s | "
          f"swap {hw.swap_gib:.0f}GiB @ {hw.swap_bw_gbs:.1f}GB/s")
    print(f"────────────────────────────────────────────────────")
    print(f"     ctx   VRAM    RAM   SWAP   tok/s   notes")
    print(f"           (GiB)  (GiB)  (GiB)")

    # Cap ladder by model's declared max if known, then keep the largest MAX_ROWS entries
    cap = m.ctx_max if m.ctx_max > 0 else CTX_LADDER[-1]
    ctxs = [c for c in CTX_LADDER if c <= cap][-MAX_ROWS:]
    if m.ctx_max and m.ctx_max not in ctxs:
        ctxs = (ctxs + [m.ctx_max])[-MAX_ROWS:]
    rows = [plan(m, hw, c) for c in sorted(set(ctxs))]
    # Treat ✓ and ⚠ rows as "above the cliff", ✗ as below.
    above = [p for p in rows if p["tok_s"] >= WARN_TOK_S][-MAX_ROWS:]
    below_all = [p for p in rows if p["tok_s"] < WARN_TOK_S]
    n_below = max(SHOW_UNUSABLE_ROWS, MIN_TOTAL_ROWS - len(above))
    below = below_all[:n_below]
    for p in above + below:
        print(fmt_row(p, m.blocks, m.ctx_max))

    # Recommend the largest context whose tok/s is still above the usability threshold.
    # Memory placement doesn't matter on its own — tok/s already reflects spill cost.
    usable = [p for p in rows if p["tok_s"] >= MIN_USABLE_TOK_S and p["layers_unfit"] == 0]
    if usable:
        best = max(usable, key=lambda p: p["ctx"])
        print(f"\n  → Recommended context: {best['ctx']} (~{best['tok_s']:.0f} tok/s)")
        print(f"\n  Apply with:")
        print(f"    docker exec -i ollama bash -c \\")
        print(f"      'printf \"FROM {m.name}\\nPARAMETER num_ctx {best['ctx']}\" "
              f"| ollama create {m.name} -f /dev/stdin'")
    else:
        print("\n  → No tested context is fast enough — consider a smaller/quantized model.")


# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser(description="Ollama model fit + tok/s estimator")
    ap.add_argument("url", nargs="?", help="Ollama blob URL to auto-fetch")
    ap.add_argument("--hardware", action="store_true", help="Re-run hardware setup")
    args = ap.parse_args()

    if args.hardware:
        setup_hardware()
        return

    hw = load_hardware()

    url = args.url
    if not url:
        url = input("Paste Ollama blob URL (or Enter to fill manually): ").strip()

    prefilled: dict = {}
    if url:
        try:
            prefilled = fetch_blob(url)
        except Exception as e:
            print(f"  ! fetch failed: {e}\n  Falling back to manual entry.")

    model = collect_model(prefilled)
    report(model, hw)


if __name__ == "__main__":
    main()
