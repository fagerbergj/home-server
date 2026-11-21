#!/usr/bin/env bash
# Thinking Machines Inkling-2-Mini launcher for llama-swap: ggml-org GGUF on a single R9700
# (card 0), looped MoE 26.4B/3.4B-active, vision on. Stock llama.cpp master (inkling2 merged
# in 29b52d39) — no PR, no stubs. IQ4_NL by default (17.6 GB, 95.5% same top token as BF16);
# QUANT=Q8_0 for the near-lossless 27.8 GB (97.6%). No spec drafter in llama.cpp: the DSpark
# drafter (mtp.safetensors) only runs under vLLM/SGLang.
set -euo pipefail

NAME="${NAME:-inkling}"
PORT="${PORT:-9990}"
IMAGE="${IMAGE:-llama-inkling:29b52d39}"
HF="${HF:-/mnt/cache/huggingface}"
QUANT="${QUANT:-IQ4_NL}"
CTX="${CTX:-32768}"
PARALLEL="${PARALLEL:-4}"
THREADS="${THREADS:-24}"
UB="${UB:-512}"
KV="${KV:-q8_0}"

S="$HF"/hub/models--ggml-org--Inkling-2-Mini-GGUF/snapshots/main
M="/root/.cache/huggingface/hub/models--ggml-org--Inkling-2-Mini-GGUF/snapshots/main/Inkling-2-Mini-$QUANT.gguf"
MM="/root/.cache/huggingface/hub/models--ggml-org--Inkling-2-Mini-GGUF/snapshots/main/mmproj-Inkling-2-Mini-Q8_0.gguf"

ARGS=()
[ "${NO_MM:-0}" != "1" ] && ARGS+=(--mmproj "$MM")
# shellcheck disable=SC2206
[ -n "${EXTRA:-}" ] && ARGS+=($EXTRA)

docker rm -f "$NAME" >/dev/null 2>&1 || true
trap 'docker logs "$NAME" > /tmp/inkling-last.log 2>&1; docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT INT TERM

docker run --init --name "$NAME" --no-healthcheck \
  --device /dev/kfd --device /dev/dri --group-add video --group-add 991 --ipc=host --shm-size 8g \
  -e HF_HUB_OFFLINE=1 -e GPU_MAX_HW_QUEUES=1 -e HIP_VISIBLE_DEVICES=0 \
  -v "$HF":/root/.cache/huggingface:ro -p "127.0.0.1:${PORT}:${PORT}" \
  "$IMAGE" \
  -m "$M" --load-mode mmap --lazy-mode on --no-host \
  --jinja --reasoning-format deepseek --temp 0.7 \
  -fa on "${ARGS[@]}" \
  --cache-type-k "$KV" --cache-type-v "$KV" --metrics --host 0.0.0.0 \
  -c "$CTX" --parallel "$PARALLEL" -t "$THREADS" -ub "$UB" -b 2048 --port "$PORT"
