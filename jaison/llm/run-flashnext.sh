#!/usr/bin/env bash
# Qwen3.8-Flash-Next launcher for llama-swap: llama.cpp (jaison/llm/mtp4 image) with the model's MTP head (PR 28243)
# and tensor parallel across all four cards (PR 28569; RCCL all-reduce needs --ipc=host). Tensor mode requires
# unquantized KV and ignores -ot, so the 28.8 GB n-gram table stays in VRAM. Q4_K_XL at 1 x 262k sits at ~30 GB/card and
# grows ~1 GB during long prefills; 2 x 262k (~33 GB) ran one card out mid-prefill and deadlocked the all-reduce (no error).
# MTP n3 raised code but cut prose; 24 threads, -ub 2048 and layer split were all slower.
set -euo pipefail

NAME="${NAME:-flash-next}"
PORT="${PORT:-9992}"
IMAGE="${IMAGE:-llama-mtp4:gfx1201}"
HF="${HF:-/mnt/cache/huggingface}"
QUANT="${QUANT:-UD-Q4_K_XL}"
SM="${SM:-tensor}"
KV="${KV:-f16}"
CTX="${CTX:-262144}"
PARALLEL="${PARALLEL:-1}"
THREADS="${THREADS:-12}"
UB="${UB:-1024}"
NMAX="${NMAX:-2}"
MMPROJ="${MMPROJ:-1}"
LOAD="${LOAD:---load-mode none}"   # images before Sep 2026 master only know --no-mmap

R="$HF"/hub/models--unsloth--Qwen3.8-Flash-Next-GGUF/snapshots
C() { echo "/root/.cache/huggingface${1#"$HF"}"; }
S=$(ls -d "$R"/*/"$QUANT" | head -1)
M=$(C "$S")/$(ls "$S" | grep -- '-00001-of-' | head -1)
D=$(C "$(ls "$R"/*/MTP/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf | head -1)")

ARGS=(-md "$D" --spec-type draft-mtp --spec-draft-n-max "$NMAX")
[ "$MMPROJ" = 1 ] && ARGS+=(--mmproj "$(C "$(ls "$R"/*/mmproj-BF16.gguf | head -1)")")
# shellcheck disable=SC2206
[ -n "${EXTRA:-}" ] && ARGS+=($EXTRA)

docker rm -f "$NAME" >/dev/null 2>&1 || true
trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT INT TERM

exec docker run --rm --init --name "$NAME" \
  --device /dev/kfd --device /dev/dri --group-add video --group-add 991 --ipc=host --shm-size 8g \
  -e HF_HUB_OFFLINE=1 -e GPU_MAX_HW_QUEUES=1 \
  -v "$HF":/root/.cache/huggingface:ro -p "127.0.0.1:${PORT}:${PORT}" \
  "$IMAGE" \
  -m "$M" $LOAD \
  --jinja --reasoning-format deepseek --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0 \
  -fa on -ngl 999 --split-mode "$SM" "${ARGS[@]}" \
  --cache-type-k "$KV" --cache-type-v "$KV" --metrics --host 0.0.0.0 \
  -c "$CTX" --parallel "$PARALLEL" -t "$THREADS" -ub "$UB" -b 2048 --port "$PORT"
