# jaison/llm — the AI box's model router

One `llm-swap` container (llama-swap) owns all four R9700s. It does not run any model itself: each entry in `llm-swap.yaml` is a `docker run` of that model's runtime image, started on startup preload or first request and stopped with `docker stop` when swapped out or its TTL expires. The media box's `llm-swap-media` (`llm/`) peers to this router for every model listed here, so clients never talk to jaison directly.

## Pieces

| File | Role |
|---|---|
| `docker-compose.yml` | The router. Host networking (it proxies to the runtimes' `127.0.0.1` ports), `/var/run/docker.sock` (it launches them), this directory mounted at its host path, `/mnt/cache` `:ro`, and `/mnt/cache/vllm` `:rw` for vLLM cache/config guards. |
| `llm-swap.Dockerfile` | `docker:cli` + bash/python3 + SHA256-verified llama-swap binary. No GPU libraries; those live in the runtime images. |
| `llm-swap.yaml` | Model table, groups, startup preloads, and per-model `cmd` / `cmdStop`. Bind-mount paths inside cmds are **host** paths because the daemon resolves them. |
| `run-flashnext-strata.sh` | Resident `qwen3.8-flash-next` launcher (Strata v0.2.19 + `strata-split-4-amd-dflash2` wrapper + `--ulimit memlock=-1:-1`). |
| `run-flashnext-rdna.sh` | Drop-in `llama-cpp-rdna-boosts` launcher for `qwen3.8-flash-next` (524k unified `q8_0` KV, 8 slots × 262k, GPU vision, strict greedy purity). |
| `run-jaison.sh` | vLLM launcher for `qwen3.8-27b` (using offline-merged `qwen3.8-27b-super-fp8` via `merge-lora-fp8.py`). |
| `run-hy4.sh` | Hy4-flash launcher (llama.cpp PR #32517, Engram table paged from NVMe via mmap + lazy rows). |
| `run-hy4-vllm.sh` | Hy4-flash launcher (vLLM ROCm TP=4 W4A16 + FP8 linears + FP8 Engram + DFly + `hy4-moe-r9700.json` tuned MoE tiles, 205k BF16 KV). |
| `run-glm.sh`, `run-deepseek.sh`, `run-flashnext.sh`, `run-mimo.sh`, `run-inkling.sh` | Cold-storage / fallback llama.cpp launchers kept in git for quick restoration when weights are copied back to `/mnt/cache`. |
| `vllm-patches/` | Tuned Triton kernel and patched vLLM sources for DFlash2 and KV sizing, bind-mounted over `vllm-radiance:0.9.3`. See its README. |
| `upstream/patched.Dockerfile` | Opt-in llama.cpp + patch-series builder (`make mtp-image`, `make glm-image`, `make inkling-image`). |
| `Makefile` | `make up` builds/pulls active runtime images and recreates the router. `make down` drains and stops the router and every runtime container. |

## Active Runtimes

| Model id | Image | Cards | Notes |
|---|---|---|---|
| `qwen3-embed` | `ghcr.io/ggml-org/llama.cpp:server-b11371` | CPU (`-t 24`) | Persistent (`ttl: 0`), preloaded at startup, `-c 16384 --parallel 4 -ub 4096 -b 4096` |
| `qwen3.8-flash-next` | `strata-server:0.2.19` | all four | Resident default (`ttl: 0`), preloaded at startup; Strata split-4 + DFlash2 + GPU vision, 416k INT8 KV (262k ctx, 8 lanes) |
| `qwen3.8-27b` | `stilldeadcode/vllm-radiance:0.9.3` | all four, TP=4 | On-demand fallback (`ttl: 3600`); offline-merged super-adapter FP8 + DFlash2, 1.18M bf16 KV (4.5× @ 262k), 131 tok/s |
| `hy4-flash` | `llama-hy4:f8d4cc41` | all four + host RAM | On-demand (`ttl: 3600`); AngelSlim Q4_K_M, Engram table paged from NVMe, text-only (`NO_MM=1`) |
| `hy4-vllm` | `vllm-hy4:rocm` | all four, TP=4 + RAM | On-demand (`ttl: 3600`); W4A16 routed experts + FP8 linears + FP8 Engram + DFly + `hy4-moe-r9700.json`, 205k bf16 KV (`NO_MM=1`) |

Runtime details:

- `qwen3.8-flash-next` — Strata v0.2.19 with the tracked `strata-split-4-amd-dflash2` wrapper, `--ulimit memlock=-1:-1` (locks 29.5 GB word/PLE tables in RAM), 416k INT8 KV pool + 16 GiB RAM conversation park cache, ~28 s cold boot. (`run-flashnext-rdna.sh` is an alternative on `llama-cpp-rdna-boosts` with 524k unified `q8_0` KV across 8 × 262k slots, 3,405 tok/s prefill, 83.1 tok/s decode without drafter, strict greedy purity.)
- `qwen3.8-27b` — `harness-hub/Qwen3.8-27B-super-adapter` offline-merged into Qwen block-FP8 (`merge-lora-fp8.py`, max FP8 rel err 0.0021) + DFlash2 int4 draft, 262k context, 6 sequences, 1.18M bf16 KV (4.50× @ 262k), **131.1 tok/s** single-stream decode (up from 73 tok/s with runtime LoRA). ~2.5 min warm boot.
- `hy4-flash` / `hy4-vllm` — Tencent Hy4-flash 220B/A11B; `hy4-vllm` runs with 415 non-expert BF16 linears packed to block-FP8 (`pack-hy4-fp8-linears.py`, 22.34 GiB/card), `hy4-moe-r9700.json` tuned R9700 MoE tiles, DFly (3.09 tok/step), and 205k bf16 KV (`MAXLEN=131072`, `NO_MM=1` to avoid 4,914-token vision profiling OOM).

Groups: `embed` is persistent (never evicted); `flash-next` is the resident default; `27b`, `hy4`, and `hy4-vllm` are exclusive on-demand groups that drain/evict the resident model on use.

Cold-storage models (`glm-5.3-flash`, `deepseek-v4.1-flash`, `mimo`, `inkling`): weights live on the media box archive (`/mnt/media/models/huggingface`); their `run-*.sh` launchers and git history bring them back when copied to `/mnt/cache`. Omni runs on the media box's RTX 3090 (`llm/llm-swap-media.yaml`).

## Data on disk (jaison)

- `/mnt/cache/huggingface` — GGUFs, mmprojs, and quantized checkpoints (`HF_HUB_OFFLINE=1`).
- `/mnt/cache/strata` — Strata engine binaries, DFlash2 pack, tokenizer, and server code.
- `/mnt/cache/vllm/qwen3.8-27b-fp8`, `/mnt/cache/vllm/qwen3.8-27b-dflash2-int4`, `/mnt/cache/vllm/qwen3.8-27b-super-adapter` — vLLM checkpoints and LoRA; `/mnt/cache/vllm/cache` and `/mnt/cache/vllm/cache-hy4` — torch.compile/Triton caches.

## Day to day

```bash
cd ~/workspace/home-server/jaison/llm
make up
curl -s localhost:11436/v1/models | jq '.data[].id'   # what the router offers
curl -s localhost:11436/running                        # what is loaded right now
docker ps                                              # runtimes: flash-next / embed / qwen38-27b-vllm / hy4 / hy4-vllm
docker logs -f flash-next                              # a runtime's own log
```

Config edits: `git pull` replaces `llm-swap.yaml`, and the bind mount follows the old inode, so `docker compose up -d --force-recreate llm-swap` (or `make up`) after pulling. Never recreate the router while a review is in flight; it stops every runtime.
