#!/usr/bin/env python3
"""Microbenchmark & autotune Hy4-flash W4A16 MoE (E=512, N=384, K=1536, topk=16) on AMD Radeon R9700."""
import json, os, sys, time
import torch
from vllm.model_executor.layers.fused_moe.fused_moe import (
    get_config_file_name,
    get_default_config,
    invoke_fused_moe_wna16_triton_kernel,
    moe_align_block_size,
)

device = torch.device("cuda:0")
E, N_TP, K, TOPK, GS = 512, 384, 1536, 16, 128
print("device_name:", torch.cuda.get_device_name(0), flush=True)
fname = get_config_file_name(E, N_TP, "int4_w4a16", None)
print("target config filename:", fname, flush=True)

w13_q = torch.randint(-2**31, 2**31 - 1, (E, 2 * N_TP, K // 8), dtype=torch.int32, device=device)
w13_s = torch.randn((E, 2 * N_TP, K // GS), dtype=torch.bfloat16, device=device).abs().clamp(min=1e-3)
w2_q = torch.randint(-2**31, 2**31 - 1, (E, K, N_TP // 8), dtype=torch.int32, device=device)
w2_s = torch.randn((E, K, N_TP // GS), dtype=torch.bfloat16, device=device).abs().clamp(min=1e-3)

CANDIDATES = [
    {"BLOCK_SIZE_M": bm, "BLOCK_SIZE_N": bn, "BLOCK_SIZE_K": bk, "GROUP_SIZE_M": gm,
     "num_warps": nw, "num_stages": 2, "waves_per_eu": wpe}
    for bm in (16, 32)
    for bn in (16, 32, 64)
    for bk in (64, 128)
    for gm in (1, 4)
    for nw in (1, 2, 4)
    for wpe in (0, 2, 4)
    if not (bm == 32 and bn == 64 and bk == 128 and nw == 1)
]
# Keep search bounded (~40 solid RDNA4 wave32 candidates)
CANDIDATES = [
    {"BLOCK_SIZE_M": bm, "BLOCK_SIZE_N": bn, "BLOCK_SIZE_K": bk, "GROUP_SIZE_M": gm,
     "num_warps": nw, "num_stages": 2, "waves_per_eu": wpe}
    for bm, bn, bk in (
        (16, 16, 64), (16, 16, 128), (16, 32, 64), (16, 32, 128),
        (16, 64, 64), (16, 64, 128), (32, 16, 64), (32, 32, 64),
        (32, 32, 128), (32, 64, 64), (32, 64, 128),
    )
    for gm in (1, 4)
    for nw in (1, 2, 4)
    for wpe in (0, 4)
    if not (bn == 16 and nw == 4) and not (bn == 64 and nw == 1)
]
print(f"sweeping {len(CANDIDATES)} configs", flush=True)


def bench_cfg(M: int, cfg: dict, iters: int = 12) -> float:
    x = torch.randn((M, K), dtype=torch.bfloat16, device=device)
    topk_ids = torch.randint(0, E, (M, TOPK), dtype=torch.int32, device=device)
    topk_w = torch.softmax(torch.randn((M, TOPK), dtype=torch.float32, device=device), dim=-1)
    sorted_ids, expert_ids, num_toks = moe_align_block_size(topk_ids, cfg["BLOCK_SIZE_M"], E)
    out1 = torch.empty((M, TOPK, 2 * N_TP), dtype=torch.bfloat16, device=device)
    x2 = torch.randn((M * TOPK, N_TP), dtype=torch.bfloat16, device=device)
    out2 = torch.empty((M, TOPK, K), dtype=torch.bfloat16, device=device)

    def run_once():
        invoke_fused_moe_wna16_triton_kernel(
            x, w13_q, out1, w13_s, None, topk_w,
            sorted_ids, expert_ids, num_toks, False, TOPK, cfg,
            None, False, True, [0, GS],
        )
        invoke_fused_moe_wna16_triton_kernel(
            x2, w2_q, out2, w2_s, None, topk_w,
            sorted_ids, expert_ids, num_toks, True, 1, cfg,
            None, False, True, [0, GS],
        )

    run_once()
    torch.cuda.synchronize()
    t0 = time.perf_counter()
    for _ in range(iters):
        run_once()
    torch.cuda.synchronize()
    return (time.perf_counter() - t0) * 1000.0 / iters  # ms per MoE layer


MS = [1, 2, 4, 6, 8, 12, 16, 24, 32, 48, 64, 128, 256, 512, 2048]
best_map = {}
for M in MS:
    dcfg = get_default_config(M, E, N_TP, K, TOPK, "int4_w4a16", None)
    try:
        def_ms = bench_cfg(M, dcfg, iters=10)
    except Exception as e:
        def_ms = float("inf")
        print(f"M={M:4d} default failed: {e}", flush=True)
    best_ms, best_c = def_ms, dcfg
    for c in CANDIDATES:
        try:
            ms = bench_cfg(M, c, iters=8)
            if ms < best_ms:
                best_ms, best_c = ms, c
        except Exception:
            pass
    best_map[str(M)] = best_c
    print(
        f"M={M:4d}: default={def_ms:6.3f}ms (x41={def_ms*41:5.1f}ms) -> "
        f"best={best_ms:6.3f}ms (x41={best_ms*41:5.1f}ms, {def_ms/best_ms:.2f}x) | {best_c}",
        flush=True,
    )

out_path = sys.argv[1] if len(sys.argv) > 1 else f"/tmp/{fname}"
with open(out_path, "w") as f:
    json.dump(best_map, f, indent=2)
print(f"SAVED {out_path}", flush=True)
