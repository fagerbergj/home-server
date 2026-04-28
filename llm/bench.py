#!/usr/bin/env python3
"""
bench.py — measure real Ollama tok/s and layer placement, compare vs llmcalc predictions.

Usage:
  ./bench.py <ollama-blob-url> [<url> ...] [--ctxs 4096,16384,32768] [--api http://host:11434]

For each URL it fetches the model spec (same way llmcalc does), then for each
requested context size:
  1. Sends a warm-up generation to load the model at that ctx
  2. Sends a real generation, reads eval_count / eval_duration → real tok/s
  3. Reads /api/ps for size_vram → real GPU/CPU split
  4. Runs llmcalc.plan() for the same ctx → predicted tok/s + placement
And prints a side-by-side table.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.request

from llmcalc import (
    fetch_blob, Model, plan, load_hardware,
)

DEFAULT_CTXS = [4096, 16384, 32768, 65536]
LONG_PROMPT = (
    "Write a detailed technical essay (target around 800 words) about distributed "
    "systems. Cover the CAP theorem, common consensus algorithms (Paxos, Raft), "
    "consistency models (linearizable, sequential, causal, eventual), and give "
    "concrete real-world examples for each. Be specific and avoid filler."
)
TARGET_GEN = 300       # request at least this many tokens for a stable measurement
WARMUP_GEN = 8


def http_post(url: str, body: dict, timeout: int = 600) -> dict:
    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )
    return json.loads(urllib.request.urlopen(req, timeout=timeout).read())


def http_get(url: str, timeout: int = 10) -> dict:
    return json.loads(urllib.request.urlopen(url, timeout=timeout).read())


def generate(api: str, model: str, num_ctx: int, num_predict: int) -> dict:
    return http_post(f"{api}/api/generate", {
        "model": model,
        "prompt": LONG_PROMPT,
        "stream": False,
        "options": {"num_ctx": num_ctx, "num_predict": num_predict},
    })


def get_loaded(api: str, model: str) -> dict | None:
    ps = http_get(f"{api}/api/ps").get("models", [])
    return next((x for x in ps if x["name"] == model or x["model"] == model), None)


def model_from_prefilled(pf: dict) -> Model:
    return Model(
        name=pf["name"],
        file_gib=pf["file_gib"], quant_bits=pf["quant_bits"],
        embedding=pf["embedding"], blocks=pf["blocks"],
        kv_heads=pf.get("kv_heads", 0), kv_len=pf.get("kv_len", 128),
        arch=pf.get("arch", "transformer"),
        ctx_max=int(pf.get("ctx_max", 0)),
        attention_blocks=int(pf.get("attention_blocks", 0)),
        ssm_state_size=int(pf.get("ssm_state_size", 0)),
        ssm_inner_size=int(pf.get("ssm_inner_size", 0)),
        experts=int(pf.get("experts", 0)),
        experts_used=int(pf.get("experts_used", 0)),
    )


def bench_url(url: str, ctxs: list[int], api: str, hw) -> tuple[str, list[dict]]:
    pf = fetch_blob(url)
    m = model_from_prefilled(pf)
    print(f"\n=== {m.name} ({m.file_gib:.1f} GiB Q{m.quant_bits}, {m.blocks} blocks) ===")

    rows = []
    for ctx in ctxs:
        if m.ctx_max and ctx > m.ctx_max:
            print(f"  skip ctx={ctx} (model max {m.ctx_max})")
            continue
        print(f"  ctx={ctx}: warming up...", flush=True)
        try:
            generate(api, m.name, ctx, WARMUP_GEN)
        except Exception as e:
            print(f"    ! warm-up failed: {e}")
            continue

        print(f"    measuring (target {TARGET_GEN} tokens)...", flush=True)
        t0 = time.time()
        try:
            resp = generate(api, m.name, ctx, TARGET_GEN)
        except Exception as e:
            print(f"    ! generate failed: {e}")
            continue
        wall = time.time() - t0

        eval_count = resp.get("eval_count", 0)
        eval_dur   = resp.get("eval_duration", 1)  # ns
        real_tok_s = eval_count / eval_dur * 1e9 if eval_dur else 0

        loaded = get_loaded(api, m.name) or {}
        size_total_b = loaded.get("size", 0)
        size_vram_b  = loaded.get("size_vram", 0)
        size_total = size_total_b / (1024 ** 3)
        size_vram  = size_vram_b  / (1024 ** 3)
        size_ram   = size_total - size_vram
        gpu_frac   = (size_vram_b / size_total_b) if size_total_b else 0
        real_layers_ram = round(m.blocks * (1 - gpu_frac))

        pred = plan(m, hw, ctx)
        rows.append({
            "ctx": ctx,
            "pred_tok_s": pred["tok_s"], "real_tok_s": real_tok_s,
            "pred_vram":  pred["vram"],  "real_vram":  size_vram,
            "pred_ram":   pred["ram"],   "real_ram":   size_ram,
            "pred_layers_ram": pred["layers_ram"], "real_layers_ram": real_layers_ram,
            "blocks": m.blocks,
            "wall_s": wall, "eval_count": eval_count,
        })
        r = rows[-1]
        print(f"    real: {real_tok_s:5.1f} t/s  vram={size_vram:.1f}G ram={size_ram:.1f}G "
              f"layers_ram={real_layers_ram}/{m.blocks}")
        print(f"    pred: {pred['tok_s']:5.1f} t/s  vram={pred['vram']:.1f}G ram={pred['ram']:.1f}G "
              f"layers_ram={pred['layers_ram']}/{m.blocks}")
    return m.name, rows


def print_table(model_results: list[tuple[str, list[dict]]]) -> None:
    print("\n" + "─" * 92)
    print(f"{'model':<22} {'ctx':>7} {'pred t/s':>9} {'real t/s':>9} {'Δ':>6} "
          f"{'pred vram':>10} {'real vram':>10} {'pred RAM L':>11} {'real RAM L':>11}")
    print("─" * 92)
    for name, rows in model_results:
        for r in rows:
            delta = (r["real_tok_s"] - r["pred_tok_s"]) / r["pred_tok_s"] * 100 if r["pred_tok_s"] else 0
            print(f"{name:<22} {r['ctx']:>7} "
                  f"{r['pred_tok_s']:>9.1f} {r['real_tok_s']:>9.1f} {delta:>+5.0f}% "
                  f"{r['pred_vram']:>9.1f}G {r['real_vram']:>9.1f}G "
                  f"{r['pred_layers_ram']:>5}/{r['blocks']:<5} "
                  f"{r['real_layers_ram']:>5}/{r['blocks']:<5}")
    print("─" * 92)


def write_csv(path: str, model_results: list[tuple[str, list[dict]]]) -> None:
    import csv
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["model", "ctx", "pred_tok_s", "real_tok_s",
                    "pred_vram_gib", "real_vram_gib", "pred_ram_gib", "real_ram_gib",
                    "pred_layers_ram", "real_layers_ram", "blocks", "eval_count"])
        for name, rows in model_results:
            for r in rows:
                w.writerow([name, r["ctx"], f"{r['pred_tok_s']:.2f}", f"{r['real_tok_s']:.2f}",
                            f"{r['pred_vram']:.2f}", f"{r['real_vram']:.2f}",
                            f"{r['pred_ram']:.2f}", f"{r['real_ram']:.2f}",
                            r["pred_layers_ram"], r["real_layers_ram"],
                            r["blocks"], r["eval_count"]])
    print(f"\nWrote {path}")


def main():
    ap = argparse.ArgumentParser(description="Benchmark Ollama vs llmcalc predictions")
    ap.add_argument("urls", nargs="+", help="Ollama blob URLs")
    ap.add_argument("--ctxs", default=",".join(str(c) for c in DEFAULT_CTXS),
                    help=f"Comma-separated context sizes (default: {DEFAULT_CTXS})")
    ap.add_argument("--api", default="http://localhost:11434", help="Ollama API URL")
    ap.add_argument("--csv", help="Optional CSV output path")
    args = ap.parse_args()

    ctxs = [int(c.strip()) for c in args.ctxs.split(",") if c.strip()]
    hw = load_hardware()
    print(f"Hardware: {hw.gpu_name} {hw.vram_gib:.0f}G @ {hw.vram_bw_gbs:.0f}GB/s | "
          f"RAM {hw.ram_gib:.0f}G @ {hw.ram_bw_gbs:.0f}GB/s | kv={hw.kv_cache_type}")

    results = []
    for url in args.urls:
        try:
            name, rows = bench_url(url, ctxs, args.api, hw)
            if rows:
                results.append((name, rows))
        except Exception as e:
            print(f"! {url}: {e}", file=sys.stderr)

    if results:
        print_table(results)
        if args.csv:
            write_csv(args.csv, results)


if __name__ == "__main__":
    main()
