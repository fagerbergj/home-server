#!/usr/bin/env bash
# Tencent Hy4-flash launcher for llama-swap: AngelSlim Q4_K_M GGUF across all four cards,
# overflow experts in host RAM, 63.5 GB Engram n-gram table paged from NVMe (mmap + lazy rows,
# same pattern as run-deepseek.sh). llama.cpp at Hy4 PR #32517 (llama-hy4:f8d4cc41; re-tag to the
# stock server-rocm release once the PR merges).
# Sampling per the model card: temperature 0.9, top_p 1.0, top_k disabled (top_k 0).
# No spec drafter in v1: the converter drops model.dfly_layers. (they're not in the GGUF) and the PR
# has no spec engine for them; it does export a draft block as extra layers — try --spec-type draft-mtp
# once layer semantics are confirmed.
set -euo pipefail

NAME="${NAME:-hy4}"
PORT="${PORT:-9991}"
IMAGE="${IMAGE:-llama-hy4:f8d4cc41}"
HF="${HF:-/mnt/cache/huggingface}"
CTX="${CTX:-524288}"
PARALLEL="${PARALLEL:-4}"
THREADS="${THREADS:-24}"
UB="${UB:-1024}"
KV="${KV:-q8_0}"
FITT="${FITT:-4096,3072,3072,3072}"   # auto-fit margins, dev0 keeps slack for the ViT/mmproj context
# TENSOR_SPLIT=1,1,1,1 forces an even model split: auto-fit's layer-boundary placement left 82-90% VRAM skew
TENSOR_SPLIT="${TENSOR_SPLIT:-}"
# SPEC=ngram-cache (or ngram-simple/ngram-map-k) enables weight-free n-gram speculative
# decoding: no drafter GGUF needed; helps most on self-similar output (code, structured text)
SPEC="${SPEC:-}"

R="$HF"/hub/models--AngelSlim--Hy4-flash-GGUF/snapshots
S=$(ls -d "$R"/*/ | head -1)
# -m needs the container-side path (/root/.cache/huggingface = $HF mounted ro)
REL="${S#"$HF"/}"
M="/root/.cache/huggingface/$REL/$(ls "$S" | grep -- '-00001-of-' | head -1)"
MM="/root/.cache/huggingface/$REL/$(ls "$S" | grep -- '^mmproj-' | head -1)"

# NO_MM=1 runs text-only: this PR build does not recognize AngelSlim's mmproj
# projector type (hy_v4_flash), so vision serving is broken until that is resolved.
ARGS=()
[ "${NO_MM:-0}" != "1" ] && ARGS+=(--mmproj "$MM")
[ -n "$TENSOR_SPLIT" ] && ARGS+=(--tensor-split "$TENSOR_SPLIT")
[ -n "$SPEC" ] && ARGS+=(--spec-type "$SPEC")
# shellcheck disable=SC2206
[ -n "${EXTRA:-}" ] && ARGS+=($EXTRA)

docker rm -f "$NAME" >/dev/null 2>&1 || true
# keep the crashed container's logs before cleanup: a premature exit is otherwise undiagnosable
trap 'docker logs "$NAME" > /tmp/hy4-last.log 2>&1; docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT INT TERM

# no exec/--rm: the EXIT trap must fire on crash so /tmp/hy4-last.log gets the container's logs
docker run --init --name "$NAME" --no-healthcheck \
  --device /dev/kfd --device /dev/dri --group-add video --group-add 991 --ipc=host --shm-size 8g \
  -e HF_HUB_OFFLINE=1 -e GPU_MAX_HW_QUEUES=1 \
  -v "$HF":/root/.cache/huggingface:ro -p "127.0.0.1:${PORT}:${PORT}" \
  "$IMAGE" \
  -m "$M" --load-mode mmap --lazy-mode on --no-host \
  --jinja --reasoning-format deepseek --temp 0.9 --top-p 1.0 \
  -fa on -fit on -fitt "$FITT" "${ARGS[@]}" \
  --cache-type-k "$KV" --cache-type-v "$KV" --metrics --host 0.0.0.0 \
  -c "$CTX" --parallel "$PARALLEL" -t "$THREADS" -ub "$UB" -b 2048 --port "$PORT"
