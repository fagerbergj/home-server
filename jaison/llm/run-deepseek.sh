#!/usr/bin/env bash
# DeepSeek-V4.1-Flash-1017 launcher for llama-swap: stock llama.cpp ROCm image, unsloth UD-IQ2_XXS across all four
# cards with auto-fit overflow in host RAM, DSpark drafter (the checkpoint's 3-stage mtp block).
# - mmap is required: the 135 GB Engram table (shard 6) stays on disk and --lazy-mode reads its rows on demand, so the
#   page cache must not be dropped after load (unlike run-glm.sh).
set -euo pipefail

NAME="${NAME:-deepseek}"
PORT="${PORT:-9992}"
IMAGE="${IMAGE:-ghcr.io/ggml-org/llama.cpp:server-rocm-b12110}"  # stock: deepseek41 + draft-dspark are upstream
HF="${HF:-/mnt/cache/huggingface}"
CTX="${CTX:-524288}"
PARALLEL="${PARALLEL:-4}"
THREADS="${THREADS:-24}"
UB="${UB:-1024}"
KV="${KV:-q8_0}"
SPEC="${SPEC:-dspark}"   # dspark | none
NMAX="${NMAX:-3}"        # the drafter has three stages
FITT="${FITT:-4096,3072,3072,3072}"   # auto-fit margins: b12110's fitter can't measure the drafter ("fitting without it"), so dev0 must leave room for dspark's 2.5 GB

M=/root/.cache/huggingface/hub/models--unsloth--DeepSeek-V4.1-Flash-1017-GGUF/snapshots/c991b28e7c109eed10a55075ddb46f830b5b3059/UD-IQ2_XXS/DeepSeek-V4.1-Flash-1017-UD-IQ2_XXS-00001-of-00006.gguf
D=/root/.cache/huggingface/hub/ds41-extra/dspark-Q8_0.gguf

ARGS=()
[ "$SPEC" = dspark ] && ARGS+=(-md "$D" --spec-type draft-dspark --spec-draft-n-max "$NMAX")
# shellcheck disable=SC2206
[ -n "${EXTRA:-}" ] && ARGS+=($EXTRA)

docker rm -f "$NAME" >/dev/null 2>&1 || true
# keep the crashed container's logs before cleanup: a premature exit is otherwise undiagnosable
trap 'docker logs "$NAME" > /tmp/deepseek-last.log 2>&1; docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT INT TERM

# no exec/--rm: the EXIT trap must fire on crash so /tmp/deepseek-last.log gets the container's logs
docker run --init --name "$NAME" --no-healthcheck \
  --device /dev/kfd --device /dev/dri --group-add video --group-add 991 --ipc=host --shm-size 8g \
  -e HF_HUB_OFFLINE=1 -e GPU_MAX_HW_QUEUES=1 \
  -v "$HF":/root/.cache/huggingface:ro -p "127.0.0.1:${PORT}:${PORT}" \
  "$IMAGE" \
  -m "$M" --load-mode mmap --lazy-mode on --no-host \
  --jinja --reasoning-format deepseek --temp 1.0 --top-p 1.0 \
  -fa on -fit on -fitt "$FITT" "${ARGS[@]}" \
  --cache-type-k "$KV" --cache-type-v "$KV" --metrics --host 0.0.0.0 \
  -c "$CTX" --parallel "$PARALLEL" -t "$THREADS" -ub "$UB" -b 2048 --port "$PORT"
