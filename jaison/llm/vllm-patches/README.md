# vllm-patches

Files `run-jaison.sh` bind-mounts into the `vllm-radiance:0.9.3` container, copied verbatim from zzpanic/qwen3.6-vllm-gfx1201-launchers @ cc89738 (`patches/`):

- `rdna_hybrid_w4a16.py` — W4A16 Triton GEMM kernel tuned for gfx1201; replaces the image's copy.
- `radiance-0.9.3/vllm/**` — vLLM sources patched for DFlash2 draft and KV pool sizing, mounted over `site-packages/vllm/`.

Pinned to 0.9.3; a new image tag needs re-checking against upstream.
