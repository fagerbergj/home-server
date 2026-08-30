# jaison/llm — the AI box's model router

One `llm-swap` container (llama-swap) owns both R9700s. It does not run any model itself: each entry in `llm-swap.yaml` is a `docker run` of that model's runtime image, started on the first request and stopped with `docker stop` when it is swapped out or its TTL expires. The media box's `llm-swap-media` (`llm/`) peers to this router for every model listed here, so clients never talk to jaison directly.

## Pieces

| File | Role |
|---|---|
| `docker-compose.yml` | The router. Host networking (it proxies to the runtimes' `127.0.0.1` ports), `/var/run/docker.sock` (it launches them), and this directory mounted at its host path (the vLLM launcher bind-mounts files from it). |
| `llm-swap.Dockerfile` | `docker:cli` + bash/python3 + the llama-swap binary. No GPU libraries; those live in the runtime images. |
| `llm-swap.yaml` | Model table, groups, and the per-model `cmd` / `cmdStop`. Bind-mount paths inside cmds are **host** paths because the daemon resolves them. |
| `run-jaison.sh` | vLLM launcher for the 27B. Reads `GPU`, `TP`, `MAXLEN`, `MAXSEQS`, `PORT`, `MODEL_DIR`, `DRAFT_DIR`, `CACHE_DIR`, `REASONING_EFFORT` from the model's `env:`. |
| `vllm-patches/` | Tuned Triton kernel and patched vLLM sources for DFlash2 and KV sizing, bind-mounted over the image. See its README. |
| `mtp/` | Dockerfile + patch for `llama-mtp:gfx1201`: llama.cpp with Flash-Next MTP draft head, HIP build. Frozen until llama.cpp PR 27836 merges. |
| `Makefile` | `make up` pulls runtime images, builds the MTP image, and starts the router. `make down` stops the router and any runtime it left running. |

## Runtimes

| Model id | Image | Cards | Notes |
|---|---|---|---|
| `qwen3.8-27b` | `stilldeadcode/vllm-radiance:0.9.3` | both, TP=2 | int4 AutoRound + DFlash2 W4A16 draft, 262k context, 2 sequences. Resident (`ttl: 0`). ~3 min boot with a warm compile cache in `/mnt/cache/vllm/cache`. |
| `qwen3.8-flash-next` | `llama-mtp:gfx1201` | both + CPU experts | UD-Q3_K_XL, `-ncmoe 8`, n-gram table pinned to CPU, MTP n3. Loading it drains and unloads the 27B. |
| `qwen3-omni-30b` | `ghcr.io/ggml-org/llama.cpp:server-vulkan` | one | Audio-capable media reader, on demand. |
| `muse-glimmer-30b` | `ghcr.io/ggml-org/llama.cpp:server-vulkan` | one | Untested candidate, on demand. |

Groups: `27b` is the resident default; `flash-next` and `extras` are exclusive, so a request for one of them swaps everything else out and the next 27B call pays the boot.

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
