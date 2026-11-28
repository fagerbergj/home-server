#!/usr/bin/env bash
# Qwen3.8-Flash-Next launcher on llama-cpp-rdna-boosts (strict greedy purity, zero engine shortcuts).
# 4x R9700 (gfx1201): UD-Q4_K_XL + mmproj-BF16, -sm tensor, --load-mode mmap --lazy-mode on (PLE in RAM),
# 524,288-token unified q8_0 KV pool across 8 slots (262,144 max/slot) at ~29 GB/card VRAM.
# Measured 2026-11-28 (v18-919794500-r368): 3,405 tok/s prefill @19k, 83.1 tok/s decode without drafter.
# Optional MTP drafter: set DRAFT=/root/.cache/huggingface/.../mtp-Qwen3.8-Flash-Next-Q8_0.gguf.
set -euo pipefail

NAME="${NAME:-flash-next}"
PORT="${PORT:-9994}"
IMAGE="${IMAGE:-ghcr.io/stew675/llama-cpp-rdna-boosts:server-rocm-10.2}"
HF="${HF:-/mnt/cache/huggingface}"
MODEL_SUB="${MODEL_SUB:-hub/qwen3.8-flash-next-q4xl}"
CTX="${CTX:-524288}"
PER_SLOT="${PER_SLOT:-262144}"
PARALLEL="${PARALLEL:-8}"
THREADS="${THREADS:-16}"
UB="${UB:-2048}"
KV="${KV:-q8_0}"
MMPROJ="${MMPROJ:-1}"
NMAX="${NMAX:-3}"

M="/root/.cache/huggingface/${MODEL_SUB}/Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf"
ARGS=()
[ "$MMPROJ" = 1 ] && ARGS+=(--mmproj "/root/.cache/huggingface/${MODEL_SUB}/mmproj-BF16.gguf")
[ -n "${DRAFT:-}" ] && ARGS+=(-md "$DRAFT" --spec-type draft-mtp --spec-draft-n-max "$NMAX")
# Splitting $EXTRA into separate CLI flags is intentional.
# shellcheck disable=SC2206
[ -n "${EXTRA:-}" ] && ARGS+=($EXTRA)

docker rm -f "$NAME" >/dev/null 2>&1 || true

exec docker run --rm --init --name "$NAME" --no-healthcheck \
  --device /dev/kfd --device /dev/dri --group-add video --group-add 991 \
  --ipc=host --shm-size 8g --ulimit memlock=-1:-1 \
  -e HF_HUB_OFFLINE=1 -e GPU_MAX_HW_QUEUES=1 \
  -v "$HF":/root/.cache/huggingface:ro -p "127.0.0.1:${PORT}:${PORT}" \
  "$IMAGE" \
  -m "$M" --load-mode mmap --lazy-mode on \
  --jinja --reasoning-format deepseek --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0 \
  -fa on -ngl 999 --split-mode tensor "${ARGS[@]}" \
  --cache-type-k "$KV" --cache-type-v "$KV" --metrics --host 0.0.0.0 \
  -c "$CTX" --parallel "$PARALLEL" -kvu --kv-unified-per-slot "$PER_SLOT" \
  -t "$THREADS" -ub "$UB" -b 2048 --port "$PORT"
