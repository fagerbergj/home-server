# vllm-patches

Files `run-jaison.sh` bind-mounts into the `vllm-radiance:0.9.3` container, copied
verbatim from zzpanic/qwen3.6-vllm-gfx1201-launchers @ cc89738 (`patches/`):

- `rdna_hybrid_w4a16.py` — the W4A16 Triton GEMM kernel with a tile table tuned for gfx1201; replaces the image's copy.
- `radiance-0.9.3/vllm/**` — two vLLM source files patched for the DFlash2 draft and the KV pool sizing, mounted over the image's `site-packages/vllm/`.

Pinned to the 0.9.3 image tag; a new image tag needs re-checking against upstream.
