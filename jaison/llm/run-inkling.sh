#!/usr/bin/env bash
# Thinking Machines Inkling-2-Mini launcher — PARKED. Taste test vs qwen3.8-27b (2026-11-21):
# decode parity single-card (31.4 tok/s vs ~35), prefill 11-12x slower (348-383 vs 4277-4732 tok/s),
# 4-way split costs 42% decode for capacity only, long sessions (42k) don't fit single-card q8 KV.
# Verdict: the 3.4B-active MoE is a fit for small machines, not for this box. Weights live on the
# media box (/mnt/media/models/huggingface/, sha256 d57542f8aea5…f45da); the llama-inkling image
# was rmi'd — rebuild from llama.cpp master 29b52d39 (inkling2 merge) if ever revisited. No spec drafter in llama.cpp: the DSpark
# drafter (mtp.safetensors) only runs under vLLM/SGLang.
set -euo pipefail

NAME="${NAME:-inkling}"
PORT="${PORT:-9990}"
IMAGE="${IMAGE:-llama-inkling:29b52d39}"
HF="${HF:-/mnt/cache/huggingface}"
QUANT="${QUANT:-Q8_0}"
CTX="${CTX:-32768}"
PARALLEL="${PARALLEL:-4}"
THREADS="${THREADS:-24}"
UB="${UB:-512}"
KV="${KV:-q8_0}"
# Spread across all four cards (27B-style): capacity move (bigger KV pool), not a speed move —
# 48 all-reduces/token on 3.4B-active layers. A/B it against single-card before assuming.
TENSOR_SPLIT="${TENSOR_SPLIT:-}"

S="$HF"/hub/models--ggml-org--Inkling-2-Mini-GGUF/snapshots/main
M="/root/.cache/huggingface/hub/models--ggml-org--Inkling-2-Mini-GGUF/snapshots/main/Inkling-2-Mini-$QUANT.gguf"
MM="/root/.cache/huggingface/hub/models--ggml-org--Inkling-2-Mini-GGUF/snapshots/main/mmproj-Inkling-2-Mini-Q8_0.gguf"

ARGS=()
[ "${NO_MM:-0}" != "1" ] && ARGS+=(--mmproj "$MM")
[ -n "$TENSOR_SPLIT" ] && ARGS+=(--tensor-split "$TENSOR_SPLIT")
# Splitting $EXTRA into separate CLI flags is intentional.
# shellcheck disable=SC2206
[ -n "${EXTRA:-}" ] && ARGS+=($EXTRA)

GPUPIN=(-e HIP_VISIBLE_DEVICES=0)   # single-card default; the split A/B needs all four visible
[ -n "$TENSOR_SPLIT" ] && GPUPIN=()

docker rm -f "$NAME" >/dev/null 2>&1 || true
trap 'docker logs "$NAME" > /tmp/inkling-last.log 2>&1; docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT INT TERM

docker run --init --name "$NAME" --no-healthcheck \
  --device /dev/kfd --device /dev/dri --group-add video --group-add 991 --ipc=host --shm-size 8g \
  -e HF_HUB_OFFLINE=1 -e GPU_MAX_HW_QUEUES=1 "${GPUPIN[@]}" \
  -v "$HF":/root/.cache/huggingface:ro -p "127.0.0.1:${PORT}:${PORT}" \
  "$IMAGE" \
  -m "$M" --load-mode mmap --lazy-mode on --no-host \
  --jinja --reasoning-format deepseek --temp 0.7 \
  -fa on "${ARGS[@]}" \
  --cache-type-k "$KV" --cache-type-v "$KV" --metrics --host 0.0.0.0 \
  -c "$CTX" --parallel "$PARALLEL" -t "$THREADS" -ub "$UB" -b 2048 --port "$PORT"
