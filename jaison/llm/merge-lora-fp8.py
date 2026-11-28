#!/usr/bin/env python3
"""Offline-merge a PEFT LoRA adapter into a block-128x128 FP8 safetensors checkpoint.

Dequantizes only the targeted FP8 weights shard-by-shard, adds (alpha / r) * (B @ A)
in FP32, and re-quantizes back to block-128x128 float8_e4m3fn + weight_scale_inv.
Untouched shards are hardlinked (or copied across filesystems) so the base checkpoint
stays intact and extra disk usage is minimized.
"""

import argparse
import json
import math
import os
import shutil
from pathlib import Path

import torch
from safetensors import safe_open
from safetensors.torch import load_file, save_file

FP8_MAX = 448.0
BLOCK = 128


def dequant_fp8_block(w: torch.Tensor, scale_inv: torch.Tensor, block: int = BLOCK) -> torch.Tensor:
    n, k = w.shape
    s = scale_inv.float()
    s_exp = s.repeat_interleave(block, dim=0)[:n, :].repeat_interleave(block, dim=1)[:, :k]
    return w.float() * s_exp


def quant_fp8_block(
    w: torch.Tensor,
    scale_dtype: torch.dtype,
    block: int = BLOCK,
) -> tuple[torch.Tensor, torch.Tensor]:
    n, k = w.shape
    bn = math.ceil(n / block)
    bk = math.ceil(k / block)
    pad_n = bn * block - n
    pad_k = bk * block - k
    wf = w.float()
    if pad_n or pad_k:
        wf_pad = torch.zeros((bn * block, bk * block), dtype=torch.float32)
        wf_pad[:n, :k] = wf
    else:
        wf_pad = wf
    amax = wf_pad.view(bn, block, bk, block).abs().amax(dim=(1, 3)).clamp(min=1e-12)
    scale = (amax / FP8_MAX).to(scale_dtype)
    s_exp = scale.float().repeat_interleave(block, dim=0)[:n, :].repeat_interleave(block, dim=1)[:, :k]
    q = (wf / s_exp).clamp(-FP8_MAX, FP8_MAX).to(torch.float8_e4m3fn)
    return q, scale


def self_test() -> None:
    torch.manual_seed(0)
    # Test both aligned and unaligned shapes
    for shape in ((512, 256), (300, 192)):
        n, k = shape
        w0 = torch.randn(n, k) * 0.05
        q0, s0 = quant_fp8_block(w0, torch.float32)
        a = torch.randn(16, k) * 0.01
        b = torch.randn(n, 16) * 0.01
        delta = 2.0 * (b @ a)
        expected = dequant_fp8_block(q0, s0) + delta
        q1, s1 = quant_fp8_block(expected, s0.dtype)
        recon = dequant_fp8_block(q1, s1)
        rel = (expected - recon).abs().mean() / expected.abs().mean()
        assert q1.dtype == torch.float8_e4m3fn and s1.shape == s0.shape and rel < 0.03, (
            f"shape={shape} rel={rel:.4f}"
        )
    print("SELF_TEST_OK", flush=True)


def link_or_copy(src: Path, dst: Path) -> None:
    if dst.exists() or dst.is_symlink():
        dst.unlink()
    try:
        os.link(src, dst)
    except OSError:
        shutil.copy2(src, dst)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", type=Path, default=Path("/vllm/qwen3.8-27b-fp8"))
    ap.add_argument("--lora", type=Path, default=Path("/vllm/qwen3.8-27b-super-adapter"))
    ap.add_argument("--out", type=Path, default=Path("/vllm/qwen3.8-27b-super-fp8"))
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()

    if args.self_test:
        self_test()
        return

    base_dir: Path = args.base
    lora_dir: Path = args.lora
    out_dir: Path = args.out
    out_dir.mkdir(parents=True, exist_ok=True)

    acfg = json.loads((lora_dir / "adapter_config.json").read_text())
    rank = int(acfg["r"])
    alpha = float(acfg["lora_alpha"])
    scaling = alpha / math.sqrt(rank) if acfg.get("use_rslora") else alpha / rank
    if acfg.get("use_dora") or acfg.get("lora_bias"):
        raise SystemExit("FATAL: DoRA / lora_bias not supported by this merger")

    cfg = json.loads((base_dir / "config.json").read_text())
    qcfg = cfg.get("quantization_config") or {}
    block_sizes = qcfg.get("weight_block_size") or [BLOCK, BLOCK]
    if list(block_sizes) != [BLOCK, BLOCK]:
        raise SystemExit(f"FATAL: unsupported weight_block_size={block_sizes}")

    idx = json.loads((base_dir / "model.safetensors.index.json").read_text())
    wm: dict[str, str] = idx["weight_map"]

    lora_path = lora_dir / "adapter_model.safetensors"
    # Map target base weight key -> (lora_A_key, lora_B_key)
    target_to_lora: dict[str, tuple[str, str]] = {}
    with safe_open(str(lora_path), framework="pt", device="cpu") as lf:
        lkeys = set(lf.keys())
        for lk in sorted(lkeys):
            if not lk.endswith(".lora_A.weight"):
                continue
            bk = lk[:-len(".lora_A.weight")] + ".lora_B.weight"
            if bk not in lkeys:
                raise SystemExit(f"FATAL: missing {bk}")
            core = lk.removeprefix("base_model.model.").removesuffix(".lora_A.weight")
            candidates = (
                core + ".weight",
                "model.language_model." + core.removeprefix("model.") + ".weight",
            )
            hit = next((c for c in candidates if c in wm), None)
            if hit is None:
                raise SystemExit(f"FATAL: unmatched LoRA key {lk}")
            target_to_lora[hit] = (lk, bk)

    # Group merged targets by base shard
    shard_targets: dict[str, list[str]] = {}
    for wkey in target_to_lora:
        shard_targets.setdefault(wm[wkey], []).append(wkey)

    all_shards = sorted(set(wm.values()))
    print(
        f"Merging {len(target_to_lora)} LoRA targets (r={rank}, alpha={alpha}, scaling={scaling}) "
        f"across {len(shard_targets)}/{len(all_shards)} shards -> {out_dir}",
        flush=True,
    )

    # Copy non-shard metadata files from base
    for item in sorted(base_dir.iterdir()):
        if item.is_dir() or item.suffix == ".safetensors" or item.name.endswith(".orig"):
            continue
        shutil.copy2(item, out_dir / item.name)

    merged_fp8 = 0
    merged_dense = 0
    max_rel_err = 0.0
    with safe_open(str(lora_path), framework="pt", device="cpu") as lf:
        for i, shard in enumerate(all_shards, 1):
            src_shard = base_dir / shard
            dst_shard = out_dir / shard
            targets = shard_targets.get(shard)
            if not targets:
                link_or_copy(src_shard, dst_shard)
                continue

            tensors = load_file(str(src_shard), device="cpu")
            for wkey in targets:
                akey, bkey = target_to_lora[wkey]
                la = lf.get_tensor(akey).float()
                lb = lf.get_tensor(bkey).float()
                delta = (lb @ la).mul_(scaling)
                w = tensors[wkey]
                skey = wkey + "_scale_inv"
                if skey in tensors and w.dtype == torch.float8_e4m3fn:
                    sc = tensors[skey]
                    w_merged = dequant_fp8_block(w, sc) + delta
                    q, sc_new = quant_fp8_block(w_merged, sc.dtype)
                    recon = dequant_fp8_block(q, sc_new)
                    rel = float((w_merged - recon).abs().mean() / w_merged.abs().mean().clamp(min=1e-12))
                    max_rel_err = max(max_rel_err, rel)
                    tensors[wkey] = q
                    tensors[skey] = sc_new
                    merged_fp8 += 1
                else:
                    tensors[wkey] = (w.float() + delta).to(w.dtype)
                    merged_dense += 1

            tmp = dst_shard.with_suffix(".safetensors.tmp")
            save_file(tensors, str(tmp))
            tmp.replace(dst_shard)
            del tensors
            if i % 10 == 0 or i == len(all_shards):
                print(f"  [{i:2d}/{len(all_shards)}] merged {merged_fp8} fp8 + {merged_dense} dense", flush=True)

    print(
        f"MERGE_DONE: fp8={merged_fp8} dense={merged_dense} max_fp8_rel_err={max_rel_err:.4f} -> {out_dir}",
        flush=True,
    )


if __name__ == "__main__":
    main()
