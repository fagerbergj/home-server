#!/usr/bin/env python3
"""Stream-quantize tencent/Hy4-flash-FP8 for jaison (4x R9700 32GB + 123GB RAM).

Transforms shard-by-shard (deletes raw shard after writing output, peak extra disk ~32 GB):
  1. Engram tables (4x 31.7 GB BF16) -> float8_e4m3fn + per-row BF16 weight_scale_inv (~64.7 GB).
  2. Routed MoE experts (82x FP8)    -> compressed-tensors symmetric INT4 W4A16 group_size=128 (~76.6 GB).
  3. Non-expert FP8 weights          -> dequantized to BF16 so quantization_config stays single-scheme.
  4. Everything else (vision, dense, DFly, norms, embeds) -> copied verbatim.

Run inside a vLLM container (needs torch, safetensors, compressed_tensors). Resumable per shard.
"""
import argparse, json, os, re, shutil, sys, urllib.request
from pathlib import Path
import torch
from safetensors.torch import load_file, save_file
from compressed_tensors.compressors.pack_quantized.helpers import (
    pack_to_int32,
    unpack_from_int32,
)

REPO = "tencent/Hy4-flash-FP8"
BASE_URL = f"https://huggingface.co/{REPO}/resolve/main"
GROUP_SIZE = 128
FP8_MAX = 448.0
EXPERT_RE = re.compile(r"^model\.layers\.\d+\.mlp\.experts\.(gate_up_proj|down_proj)$")
ENGRAM_RE = re.compile(r"^model\.layers\.\d+\.engram_layer\.multi_head_embedding\.embedding\.weight$")


def download(url: str, dst: Path) -> None:
    tmp = dst.with_suffix(dst.suffix + ".part")
    for attempt in range(1, 6):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "hy4-quant/1"})
            with urllib.request.urlopen(req, timeout=120) as r, open(tmp, "wb") as f:
                shutil.copyfileobj(r, f, length=16 * 1024 * 1024)
            tmp.replace(dst)
            return
        except Exception as e:
            if attempt == 5:
                raise
            print(f"  retry {attempt}/5 for {dst.name}: {e}", flush=True)


def dequant_fp8_block128(w: torch.Tensor, scale_inv: torch.Tensor) -> torch.Tensor:
    """Dequantize 2D [N, K] or 3D [E, N, K] FP8 tensor with 128x128 block scale_inv."""
    orig_ndim = w.ndim
    if orig_ndim == 2:
        w = w.unsqueeze(0)
        scale_inv = scale_inv.unsqueeze(0)
    E, N, K = w.shape
    s = scale_inv.float()
    # Expand block scales to [E, N, K] via repeat_interleave (handles non-multiple-of-128 edges too)
    s_exp = s.repeat_interleave(128, dim=-2)[:, :N, :].repeat_interleave(128, dim=-1)[:, :, :K]
    out = w.float() * s_exp
    return out.squeeze(0) if orig_ndim == 2 else out


def quant_engram_fp8(w: torch.Tensor, chunk_rows: int = 4_000_000) -> tuple[torch.Tensor, torch.Tensor]:
    """Pack [rows, dim] BF16 Engram table -> (float8_e4m3fn [rows, dim], bfloat16 [rows])."""
    rows, dim = w.shape
    q_out = torch.empty((rows, dim), dtype=torch.float8_e4m3fn)
    s_out = torch.empty((rows,), dtype=torch.bfloat16)
    for start in range(0, rows, chunk_rows):
        end = min(start + chunk_rows, rows)
        c = w[start:end].float()
        amax = c.abs().amax(dim=-1).clamp(min=1e-12)
        scale = (amax / FP8_MAX).to(torch.bfloat16)
        q = (c / scale.float().unsqueeze(-1)).clamp(-FP8_MAX, FP8_MAX).to(torch.float8_e4m3fn)
        q_out[start:end] = q
        s_out[start:end] = scale
    return q_out, s_out


def quant_experts_w4a16(w_fp8: torch.Tensor, scale_inv: torch.Tensor, chunk_e: int = 32) -> tuple[torch.Tensor, torch.Tensor]:
    """Dequant [E, N, K] FP8 experts -> symmetric INT4 group_size=128 packed along K."""
    E, N, K = w_fp8.shape
    assert K % GROUP_SIZE == 0 and K % 8 == 0, f"bad expert shape {(E, N, K)}"
    packed_out = torch.empty((E, N, K // 8), dtype=torch.int32)
    scale_out = torch.empty((E, N, K // GROUP_SIZE), dtype=torch.bfloat16)
    for start in range(0, E, chunk_e):
        end = min(start + chunk_e, E)
        w = dequant_fp8_block128(w_fp8[start:end], scale_inv[start:end])
        wg = w.view(end - start, N, K // GROUP_SIZE, GROUP_SIZE)
        amax = wg.abs().amax(dim=-1).clamp(min=1e-12)
        sc = (amax / 7.0).to(torch.bfloat16)
        q = torch.round(wg / sc.float().unsqueeze(-1)).clamp(-8, 7).to(torch.int8)
        q2d = q.view((end - start) * N, K)
        packed_out[start:end] = pack_to_int32(q2d, num_bits=4).view(end - start, N, K // 8)
        scale_out[start:end] = sc
    return packed_out, scale_out


def build_quant_config() -> dict:
    return {
        "quant_method": "compressed-tensors",
        "format": "pack-quantized",
        "quantization_status": "compressed",
        "global_compression_ratio": None,
        "config_groups": {
            "group_0": {
                "targets": ["FusedMoE"],
                "weights": {
                    "num_bits": 4,
                    "type": "int",
                    "symmetric": True,
                    "strategy": "group",
                    "group_size": GROUP_SIZE,
                    "dynamic": False,
                    "actorder": None,
                    "observer": "minmax",
                },
                "input_activations": None,
                "output_activations": None,
            }
        },
        "ignore": [
            "lm_head",
            "re:.*embed_tokens.*",
            "re:.*engram_layer.*",
            "re:.*self_attn.*",
            "re:.*shared_experts.*",
            "re:.*routed_expert_.*",
            "re:.*hc_.*",
            "re:^vit\\..*",
            "re:.*dfly_layers.*",
            "re:^model\\.layers\\.0\\.mlp\\..*",
        ],
    }


def self_test() -> None:
    torch.manual_seed(0)
    # 1. Engram FP8 roundtrip
    x = torch.randn(1024, 96, dtype=torch.bfloat16)
    q, s = quant_engram_fp8(x, chunk_rows=512)
    recon = q.float() * s.float().unsqueeze(-1)
    rel = (x.float() - recon).abs().mean() / x.float().abs().mean()
    assert q.dtype == torch.float8_e4m3fn and s.dtype == torch.bfloat16 and rel < 0.05, f"engram rel={rel}"
    # 2. Expert W4A16 roundtrip
    w = torch.randn(4, 256, 256)
    # Fake FP8 + block-128 scale_inv
    ws = w.view(4, 2, 128, 2, 128).abs().amax(dim=(2, 4)).clamp(min=1e-12) / FP8_MAX
    ws_bf16 = ws.to(torch.bfloat16)
    w_fp8 = (w / ws_bf16.float().repeat_interleave(128, 1).repeat_interleave(128, 2)).clamp(-FP8_MAX, FP8_MAX).to(torch.float8_e4m3fn)
    packed, sc = quant_experts_w4a16(w_fp8, ws_bf16, chunk_e=2)
    assert packed.shape == (4, 256, 32) and packed.dtype == torch.int32
    assert sc.shape == (4, 256, 2) and sc.dtype == torch.bfloat16
    unpacked = unpack_from_int32(packed.view(-1, 32), num_bits=4, shape=torch.Size([4 * 256, 256])).view(4, 256, 256)
    w_rec = (unpacked.float().view(4, 256, 2, 128) * sc.float().unsqueeze(-1)).view(4, 256, 256)
    rel2 = (w - w_rec).abs().mean() / w.abs().mean()
    assert rel2 < 0.15, f"w4a16 rel={rel2}"
    print(f"SELF_TEST_OK engram_rel={rel:.4f} w4a16_rel={rel2:.4f}", flush=True)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=Path("/root/.cache/huggingface/hub/hy4-flash-vllm-w4a16"))
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        self_test()
        return

    out: Path = args.out
    out.mkdir(parents=True, exist_ok=True)
    raw_dir = out / ".raw"
    raw_dir.mkdir(exist_ok=True)

    # 1. Fetch metadata / tokenizer files
    meta_files = [
        "config.json", "generation_config.json", "model.safetensors.index.json",
        "chat_template.jinja", "processor_config.json", "preprocessor_config.json",
        "tokenizer.json", "tokenizer_config.json", "special_tokens_map.json",
        "video_preprocessor_config.json",
    ]
    for mf in meta_files:
        dst = out / (mf + ".orig" if mf in ("config.json", "model.safetensors.index.json") else mf)
        if not dst.exists():
            try:
                download(f"{BASE_URL}/{mf}", dst)
            except Exception as e:
                if mf in ("config.json", "model.safetensors.index.json"):
                    raise
                print(f"  optional {mf} skipped: {e}", flush=True)

    orig_index = json.loads((out / "model.safetensors.index.json.orig").read_text())
    wm = orig_index["weight_map"]
    shards = sorted(set(wm.values()))
    new_wm: dict[str, str] = {}

    for idx, shard in enumerate(shards, 1):
        out_shard = out / shard
        map_cache = out / f".map_{shard}.json"
        if out_shard.exists() and map_cache.exists():
            new_wm.update(json.loads(map_cache.read_text()))
            continue

        raw_shard = raw_dir / shard
        print(f"[{idx:3d}/{len(shards)}] {shard}: downloading...", flush=True)
        if not raw_shard.exists():
            download(f"{BASE_URL}/{shard}", raw_shard)

        tensors = load_file(str(raw_shard), device="cpu")
        out_tensors: dict[str, torch.Tensor] = {}
        consumed_scales: set[str] = set()

        for k, v in tensors.items():
            if k.endswith("_scale_inv"):
                continue
            if ENGRAM_RE.match(k):
                print(f"  engram FP8: {k} {tuple(v.shape)}", flush=True)
                q, s = quant_engram_fp8(v)
                out_tensors[k] = q
                out_tensors[k[:-len(".weight")] + ".weight_scale_inv"] = s
            elif EXPERT_RE.match(k):
                sk = k + "_scale_inv"
                assert sk in tensors, f"missing scale {sk}"
                consumed_scales.add(sk)
                print(f"  expert W4A16: {k} {tuple(v.shape)}", flush=True)
                packed, sc = quant_experts_w4a16(v, tensors[sk])
                out_tensors[k + ".weight_packed"] = packed
                out_tensors[k + ".weight_scale"] = sc
            elif k + "_scale_inv" in tensors:
                sk = k + "_scale_inv"
                consumed_scales.add(sk)
                out_tensors[k] = dequant_fp8_block128(v, tensors[sk]).to(torch.bfloat16)
            else:
                out_tensors[k] = v

        tmp_out = out_shard.with_suffix(".safetensors.tmp")
        save_file(out_tensors, str(tmp_out))
        tmp_out.replace(out_shard)
        shard_map = {k: shard for k in out_tensors}
        map_cache.write_text(json.dumps(shard_map))
        new_wm.update(shard_map)
        del tensors, out_tensors
        raw_shard.unlink(missing_ok=True)
        print(f"  wrote {shard} ({out_shard.stat().st_size / 1e9:.2f} GB)", flush=True)

    # 2. Write final index + config.json
    (out / "model.safetensors.index.json").write_text(
        json.dumps({"metadata": orig_index.get("metadata", {}), "weight_map": new_wm}, indent=2)
    )
    cfg = json.loads((out / "config.json.orig").read_text())
    qc = build_quant_config()
    cfg["quantization_config"] = qc
    if "text_config" in cfg:
        cfg["text_config"]["quantization_config"] = qc
        cfg["text_config"]["engram_fp8_embedding"] = True
    (out / "config.json").write_text(json.dumps(cfg, indent=2))
    shutil.rmtree(raw_dir, ignore_errors=True)
    for f in out.glob(".map_*.json"):
        f.unlink(missing_ok=True)
    print(f"QUANT_COMPLETE: {len(new_wm)} tensors in {len(shards)} shards -> {out}", flush=True)


if __name__ == "__main__":
    main()
