# jaison/llm — the AI box's model router

One `llm-swap` container (llama-swap) owns both R9700s. It does not run any model itself: each entry in `llm-swap.yaml` is a `docker run` of that model's runtime image, started on the first request and stopped with `docker stop` when it is swapped out or its TTL expires. The media box's `llm-swap-media` (`llm/`) peers to this router for every model listed here, so clients never talk to jaison directly.

## Pieces

| File | Role |
|---|---|
| `docker-compose.yml` | The router. Host networking (it proxies to the runtimes' `127.0.0.1` ports), `/var/run/docker.sock` (it launches them), and this directory mounted at its host path (the vLLM launcher bind-mounts files from it). |
| `llm-swap.Dockerfile` | `docker:cli` + bash/python3 + the llama-swap binary. No GPU libraries; those live in the runtime images. |
| `llm-swap.yaml` | Model table, groups, and the per-model `cmd` / `cmdStop`. Bind-mount paths inside cmds are **host** paths because the daemon resolves them. |
| `run-flashnext.sh` | Qwen3.8-Flash-Next launcher (llama.cpp, tensor split). Knobs: `QUANT`, `SM`, `KV`, `CTX`, `PARALLEL`, `THREADS`, `UB`, `NMAX`, `MMPROJ`, `LOAD`. |
| `run-glm.sh` | GLM-5.3-Flash launcher (llama.cpp). Knobs: `SPEC` (mtp/dflash/none), `NMAX`, `KV`, `CTX`, `PARALLEL`, `NCMOE`/`TS` (placement; empty `NCMOE` = auto-fit with `FITT` margins), `MMPROJ`. |
| `run-mimo.sh` | MiMo-V2.6-Flash launcher (llama.cpp). Reads `PORT`, `NAME`, `NCMOE`, `CTX`, `PARALLEL`, `THREADS` from the model's `env:`. |
| `mimo/` | Scratch image `llama-mimo:gfx1201`: upstream llama.cpp + `mimo2-dflash.patch` (layer-input hooks for the drafter, DFlash value scale, no tied lm_head). `make mimo-image`. |
| `run-jaison.sh` | vLLM launcher for the 27B. Reads `GPU`, `TP`, `MAXLEN`, `MAXSEQS`, `PORT`, `MODEL_DIR`, `DRAFT_DIR`, `CACHE_DIR`, `REASONING_EFFORT` from the model's `env:`. |
| `vllm-patches/` | Tuned Triton kernel and patched vLLM sources for DFlash2 and KV sizing, bind-mounted over the image. See its README. |
| `mtp4/` | Dockerfile + PR diffs for `llama-mtp4:gfx1201`: llama.cpp master + PR 28243 (Flash-Next MTP) + PR 28569 (tensor split for qwen4exp), RCCL. `make mtp-image`. |
| `Makefile` | `make up` pulls runtime images, builds the MTP image, and starts the router. `make down` stops the router and any runtime it left running. |

## Runtimes

| Model id | Image | Cards | Notes |
|---|---|---|---|
| `qwen3.8-27b` | `stilldeadcode/vllm-radiance:0.9.3` | both, TP=2 | int4 AutoRound + DFlash2 W4A16 draft, 262k context, 2 sequences. Resident (`ttl: 0`). ~3 min boot with a warm compile cache in `/mnt/cache/vllm/cache`. |
| `qwen3.8-flash-next` | `llama-mtp4:gfx1201` | all four, tensor split | UD-Q4_K_XL (n-gram table in VRAM; tensor mode ignores -ot), RCCL tensor parallel, MTP shared-Q8_0 n2, f16 KV, 1 slot x 262k (two slots run a card out of memory mid-prefill and hang the tensor-parallel all-reduce). ~67 t/s code, ~48 prose; prefill ~1,100 t/s at 30k and 560 at 252k (recall verified to 252k). Loading it drains and unloads the 27B. |
| `mimo-v2.6-flash` | `llama-mimo:gfx1201` | all four + host RAM | MXFP4 (lossless, experts ship in MXFP4), 23 expert layers in RAM, DFlash drafter, Q8_0 vision/audio projector, 4 slots x 128k (longer prompts lose recall on ROCm). ~42 t/s single, ~46 aggregate at 4 streams, ~600 t/s prefill. `run-mimo.sh` drops the page cache after boot (no-mmap load leaves it full and kswapd stalls decode). Loading it drains and unloads the 27B. |
| `glm-5.3-flash` | `llama-glm:gfx1201` | all four + host RAM | unsloth UD-IQ4_XS, experts of 23 layers (~76 GiB) in RAM, GLM's MTP head at depth 2, q8_0 KV, 4 slots x 256k. ~22 t/s code, ~17 prose, ~28 aggregate at 4 streams. Built with `glm/rdna4-sparse.patch` so attention reads only the indexer's 2048 top-k keys: prefill 227 t/s at 30k, 196 at 106k, 174 at 170k (a cold 170k prompt takes ~16 min). `--no-host` is required: pinned host buffers fault the GPU when a slot restores cached state. Loading it drains and unloads the 27B. |
| `qwen3-omni-30b` | `ghcr.io/ggml-org/llama.cpp:server-vulkan` | one | Audio-capable media reader, on demand. |
| `muse-glimmer-30b` | `ghcr.io/ggml-org/llama.cpp:server-vulkan` | one | Untested candidate, on demand. |

Groups: `27b` is the resident default; `flash-next`, `mimo`, `glm` and `extras` are exclusive, so a request for one of them swaps everything else out and the next 27B call pays the boot.

## Data on disk (jaison)

- `/mnt/cache/huggingface` — GGUFs and mmprojs (HF cache layout, `HF_HUB_OFFLINE=1`).
- `/mnt/cache/vllm/qwen3.8-27b-autoround`, `/mnt/cache/vllm/qwen3.8-27b-dflash2-int4` — vLLM checkpoints; `/mnt/cache/vllm/cache` — torch.compile cache.

## Day to day

```bash
cd ~/workspace/home-server/jaison/llm && set -a && . ../../.env && set +a
make up
curl -s localhost:11436/v1/models | jq '.data[].id'   # what the router offers
curl -s localhost:11436/running                        # what is loaded right now
docker ps                                              # runtimes: qwen38-27b-vllm / flash-next / omni / muse
docker logs -f qwen38-27b-vllm                         # a runtime's own log
```

Config edits: `git pull` replaces `llm-swap.yaml`, and the bind mount follows the old inode, so `docker compose up -d --force-recreate llm-swap` (or `make up`) after pulling. Never recreate the router while a review is in flight; it stops every runtime.
