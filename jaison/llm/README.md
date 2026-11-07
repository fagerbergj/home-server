# jaison/llm — the AI box's model router

One `llm-swap` container (llama-swap) owns all four R9700s. It does not run any model itself: each entry in `llm-swap.yaml` is a `docker run` of that model's runtime image, started on the first request and stopped with `docker stop` when it is swapped out or its TTL expires. The media box's `llm-swap-media` (`llm/`) peers to this router for every model listed here, so clients never talk to jaison directly.

## Pieces

| File | Role |
|---|---|
| `docker-compose.yml` | The router. Host networking (it proxies to the runtimes' `127.0.0.1` ports), `/var/run/docker.sock` (it launches them), and this directory mounted at its host path (the vLLM launcher bind-mounts files from it). |
| `llm-swap.Dockerfile` | `docker:cli` + bash/python3 + the llama-swap binary. No GPU libraries; those live in the runtime images. |
| `llm-swap.yaml` | Model table, groups, and the per-model `cmd` / `cmdStop`. Bind-mount paths inside cmds are **host** paths because the daemon resolves them. |
| `run-flashnext.sh` | Qwen3.8-Flash-Next launcher (llama.cpp, tensor split). Knobs: `QUANT`, `SM`, `KV`, `CTX`, `PARALLEL`, `THREADS`, `UB`, `NMAX`, `MMPROJ`, `LOAD`. |
| `run-glm.sh` | GLM-5.3-Flash launcher (llama.cpp). Knobs: `QUANT`, `SPEC` (mtp/dflash/none), `NMAX`, `KV`, `CTX`, `PARALLEL`, `NCMOE`/`TS` (placement; empty `NCMOE` = auto-fit with `FITT` margins), `MMPROJ`. |
| `run-mimo.sh` | MiMo-V2.6-Flash launcher (llama.cpp). Reads `PORT`, `NAME`, `NCMOE`, `CTX`, `PARALLEL`, `THREADS` from the model's `env:`. |
| `run-jaison.sh` | vLLM launcher for the 27B. Reads `GPU`, `TP`, `MAXLEN`, `MAXSEQS`, `PORT`, `MODEL_DIR`, `DRAFT_DIR`, `CACHE_DIR`, `REASONING_EFFORT` from the model's `env:`. |
| `vllm-patches/` | Tuned Triton kernel and patched vLLM sources for DFlash2 and KV sizing, bind-mounted over the image. See its README. |
| `upstream/patched.Dockerfile` | llama.cpp + one model's patch series, gfx1201 + RCCL. `mtp4/patches` (Flash-Next's shared MTP head) builds `llama-mtp4:b12110-port` (`make mtp-image`; base pinned by MTP_COMMIT/MTP_BASE — dry-run the series on a new tree before bumping); `glm/patches` (RDNA4 sparse FA) builds `llama-glm:b11580-p1` (`make glm-image`). Each `patches/README.md` says what is carried and why. |
| `Makefile` | `make up` pulls runtime images, builds the patched images, and starts the router. `make down` stops the router and any runtime it left running. |

## Runtimes

| Model id | Image | Cards | Notes |
|---|---|---|---|
| `qwen3.8-27b` | `stilldeadcode/vllm-radiance:0.9.3` | all four, TP=4 | FP8 (Qwen block-fp8) + DFlash2 int4 draft, 262k context, 6 sequences, bf16 KV. Resident (`ttl: 0`). ~3 min boot with a warm compile cache in `/mnt/cache/vllm/cache`. |
| `glm-5.3-flash` | `llama-glm:b11580-p1` | all four + host RAM | unsloth UD-IQ4_XS, experts of 23 layers (~76 GiB) in RAM, GLM's MTP head at depth 2, q8_0 KV, 4 slots x 256k. ~22 t/s code, ~17 prose, ~28 aggregate at 4 streams. Built with `glm/patches` so attention reads only the indexer's 2048 top-k keys: prefill 227 t/s at 30k, 196 at 106k, 174 at 170k (a cold 170k prompt takes ~16 min). `--no-host` is required: pinned host buffers fault the GPU when a slot restores cached state. Loading it drains and unloads the 27B. |
| `deepseek-v4.1-flash` | `ghcr.io/ggml-org/llama.cpp:server-rocm-b12110` | all four + host RAM | stock image — DeepSeek-V4.1 and the DSpark drafter are upstream. unsloth UD-IQ2_XXS, DSpark n3, q8_0 KV, 4 x 128k slots, cold load ~12 min. The 135 GB Engram table (shard 6) stays on disk: `mmap` + `--lazy-mode` read its rows on demand, so the page cache must not be dropped after load. b12110's fitter can't measure the drafter ("fitting without it"), so `-fitt` margins reserve dev0's 2.5 GB for dspark — without them the drafter OOMs at load (see run-deepseek.sh; crash logs land in the router container's /tmp/deepseek-last.log). |
| `qwen3.8-flash-next` | `llama-mtp4:b12110-port` | all four | llama.cpp b12110 + `mtp4/patches` (the shared MTP head borrows the target's embeddings; PR 28243 never landed upstream). unsloth UD-Q4_K_XL tensor-split across all four cards, shared head n2, f16 KV (tensor mode requires unquantized KV and ignores -ot; the 28.8 GB n-gram table stays in VRAM), 1 x 262k slot at ~30 GB/card. ~45 s load warm. |

Groups: `27b` is the resident default; `glm` is exclusive, so a request for it swaps the 27B out and the next 27B call pays the boot.

MiMo is in cold storage on the media box (`/mnt/media/models/huggingface`); `run-mimo.sh` and its git history bring it back. Flash-Next returned on b12110 (see Runtimes). Omni moved to the media box's 3090 (`llm/llm-swap-media.yaml`).

## Data on disk (jaison)

- `/mnt/cache/huggingface` — GGUFs and mmprojs (HF cache layout, `HF_HUB_OFFLINE=1`).
- `/mnt/cache/vllm/qwen3.8-27b-fp8`, `/mnt/cache/vllm/qwen3.8-27b-dflash2-int4` — vLLM checkpoints; `/mnt/cache/vllm/cache` — torch.compile cache.

## Day to day

```bash
cd ~/workspace/home-server/jaison/llm && set -a && . ../../.env && set +a
make up
curl -s localhost:11436/v1/models | jq '.data[].id'   # what the router offers
curl -s localhost:11436/running                        # what is loaded right now
docker ps                                              # runtimes: qwen38-27b-vllm / glm
docker logs -f qwen38-27b-vllm                         # a runtime's own log
```

Config edits: `git pull` replaces `llm-swap.yaml`, and the bind mount follows the old inode, so `docker compose up -d --force-recreate llm-swap` (or `make up`) after pulling. Never recreate the router while a review is in flight; it stops every runtime.
