#!/usr/bin/env python3
"""In-place pack Hy4-flash non-expert BF16 linears -> compressed-tensors block-128x128 OCP FP8.

Leaves RoutedExperts (W4A16 INT4), Engram (FP8), vision, DFly, embed_tokens, lm_head,
and iHC/router weights untouched. Saves ~2.7 GiB/card VRAM (~11 GB total) for KV cache.
"""
import argparse, json, re, shutil
from pathlib import Path
import torch
from safetensors.torch import load_file, save_file

FP8_MAX = 448.0
TARGET_RE = re.compile(
    r"^model\.layers\.(\d+)\.("
    r"self_attn\.(q_a_proj|kv_a_proj_with_mqa|q_b_proj|kv_b_proj|linear_gate|o_proj)"
    r"|mlp\.shared_experts\.(gate_proj|up_proj|down_proj)"
    r"|mlp\.routed_expert_(down_proj|up_proj)"
    r")\.weight$"
)


def quant_fp8_block128(w: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
    N, K = w.shape
    assert N % 128 == 0 and K % 128 == 0, f"unaligned {w.shape}"
    wf = w.float().view(N // 128, 128, K // 128, 128)
    amax = wf.abs().amax(dim=(1, 3)).clamp(min=1e-12)
    scale = (amax / FP8_MAX).to(torch.float32)  # [N//128, K//128]
    s_exp = scale.repeat_interleave(128, dim=0).repeat_interleave(128, dim=1)
    q = (w.float() / s_exp).clamp(-FP8_MAX, FP8_MAX).to(torch.float8_e4m3fn)
    return q, scale


def build_mixed_quant_config(ignored_unaligned: list[str]) -> dict:
    return {
        "quant_method": "compressed-tensors",
        "format": "mixed-precision",
        "quantization_status": "compressed",
        "global_compression_ratio": None,
        "config_groups": {
            "group_0": {
                "format": "pack-quantized",
                "targets": ["RoutedExperts"],
                "weights": {
                    "num_bits": 4,
                    "type": "int",
                    "symmetric": True,
                    "strategy": "group",
                    "group_size": 128,
                    "dynamic": False,
                    "actorder": None,
                    "observer": "minmax",
                },
                "input_activations": None,
                "output_activations": None,
            },
            "group_1": {
                "format": "float-quantized",
                "targets": ["Linear"],
                "weights": {
                    "num_bits": 8,
                    "type": "float",
                    "symmetric": True,
                    "strategy": "block",
                    "block_structure": [128, 128],
                    "dynamic": False,
                },
                "input_activations": {
                    "num_bits": 8,
                    "type": "float",
                    "symmetric": True,
                    "strategy": "group",
                    "group_size": 128,
                    "dynamic": True,
                },
                "output_activations": None,
            },
        },
        "ignore": [
            "lm_head",
            "re:.*embed_tokens.*",
            "re:.*engram_layer.*",
            "re:.*indexer.*",
            "re:.*hc_.*",
            "re:.*mlp\\.gate$",
            "re:^vit\\..*",
            "re:^visual\\..*",
            "re:.*dfly_layers.*",
            "re:.*layers\\.0\\.mlp\\..*",
            *sorted(set(ignored_unaligned)),
        ],
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", type=Path, default=Path("/root/.cache/huggingface/hub/hy4-flash-vllm-w4a16"))
    args = ap.parse_args()
    d: Path = args.dir
    idx_p = d / "model.safetensors.index.json"
    cfg_p = d / "config.json"
    idx = json.loads(idx_p.read_text())
    wm: dict[str, str] = idx["weight_map"]

    # Find shards containing target BF16 linears
    shard_to_keys: dict[str, list[str]] = {}
    for k, sh in wm.items():
        if TARGET_RE.match(k):
            shard_to_keys.setdefault(sh, []).append(k)

    print(f"Scanning {len(shard_to_keys)} shards for target BF16 linears...", flush=True)
    converted, saved_bytes = 0, 0
    ignored_unaligned: list[str] = []

    for sh, keys in sorted(shard_to_keys.items()):
        sp = d / sh
        tensors = load_file(str(sp), device="cpu")
        changed = False
        for k in keys:
            v = tensors[k]
            if v.dtype != torch.bfloat16 or v.ndim != 2:
                continue
            if v.shape[0] % 128 != 0 or v.shape[1] % 128 != 0:
                mod = k[:-len(".weight")]
                ignored_unaligned.append(f"re:.*{re.escape(mod)}$")
                continue
            q, sc = quant_fp8_block128(v)
            saved_bytes += v.nbytes - q.nbytes - sc.nbytes
            tensors[k] = q
            sk = k[:-len(".weight")] + ".weight_scale"
            tensors[sk] = sc
            wm[sk] = sh
            converted += 1
            changed = True
        if changed:
            tmp = sp.with_suffix(".safetensors.tmp")
            save_file(tensors, str(tmp))
            tmp.replace(sp)

    idx["weight_map"] = wm
    idx_p.write_text(json.dumps(idx, indent=2))
    cfg = json.loads(cfg_p.read_text())
    qc = build_mixed_quant_config(ignored_unaligned)
    cfg["quantization_config"] = qc
    if "text_config" in cfg:
        cfg["text_config"]["quantization_config"] = qc
    cfg_p.write_text(json.dumps(cfg, indent=2))
    print(
        f"FP8_LINEARS_DONE: converted={converted} tensors | saved={saved_bytes/1e9:.2f} GB "
        f"({saved_bytes/4e9:.2f} GB/card) | unaligned_ignored={len(ignored_unaligned)}",
        flush=True,
    )


if __name__ == "__main__":
    main()
