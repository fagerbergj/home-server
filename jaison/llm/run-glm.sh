#!/usr/bin/env bash
# GLM-5.3-Flash launcher for llama-swap: llama.cpp (jaison/llm/glm image, PR 27754 branch), unsloth UD-IQ4_XS across
# all four cards with the overflow experts in host RAM, speculating with GLM's own MTP head.
# - --no-host: pinned host buffers make SDMA fault ("Memory access fault ... page not present") when a slot restores a
#   prompt-cache entry or context checkpoint; plain RAM costs nothing at -ub 1024.
# - Placement: CPU experts for layers 3-25 (--n-cpu-moe 26), full layers 26-46 split 2/7/6/6 across HIP devices 0-3,
#   leaving 4-6 GB free per card. Auto-fit (NCMOE= empty, -fitt margins) splits single layers' experts across CPU
#   and GPU and decoded 5-10% slower. HIP device order differs from rocm-smi's; device 3 also holds the MTP context.
# - MTP n2 beat DFlash2 (acceptance 0.8 vs 0.4-0.55 on this quant; DFlash2 slowed prose below no speculation).
# - Weights are read without mmap (157 GB file vs 126 GB RAM); the page cache is dropped once healthy.
set -euo pipefail

NAME="${NAME:-glm}"
PORT="${PORT:-9998}"
IMAGE="${IMAGE:-llama-glm:gfx1201}"
HF="${HF:-/mnt/cache/huggingface}"
QUANT="${QUANT:-UD-IQ4_XS}"
CTX="${CTX:-1048576}"
PARALLEL="${PARALLEL:-4}"
THREADS="${THREADS:-24}"
UB="${UB:-1024}"
KV="${KV:-q8_0}"
SPEC="${SPEC:-mtp}"   # mtp | dflash | none
NMAX="${NMAX:-2}"
NCMOE="${NCMOE-26}"
TS="${TS:-28,7,6,6}"
FITT="${FITT:-6144,3072,3072,3072}"   # auto-fit margins, used only when NCMOE is empty
MMPROJ="${MMPROJ:-0}"

S=$(ls -d "$HF"/hub/models--unsloth--GLM-5.3-Flash-GGUF/snapshots/*/"$QUANT" | head -1)
M=/root/.cache/huggingface${S#"$HF"}/$(ls "$S" | grep -- '-00001-of-' | head -1)

if [ -n "$NCMOE" ]; then
  ARGS=(-ngl 999 --n-cpu-moe "$NCMOE" -ts "$TS")
else
  ARGS=(-fitt "$FITT")
fi
case "$SPEC" in
  mtp)    ARGS+=(--spec-type draft-mtp --spec-draft-n-max "$NMAX") ;;
  dflash) DS=$(ls -d "$HF"/hub/models--Anbeeld--GLM-5.3-Flash-DFlash2-GGUF/snapshots/* | head -1)
          ARGS+=(-md "/root/.cache/huggingface${DS#"$HF"}/GLM-5.3-Flash-DFlash2-Q4_K_M.gguf"
                 --spec-type draft-dflash --spec-draft-n-max "$NMAX" --spec-draft-p-min 0.3) ;;
  none)   ;;
esac
if [ "$MMPROJ" = 1 ]; then
  P=$(ls "$HF"/hub/models--unsloth--GLM-5.3-Flash-GGUF/snapshots/*/mmproj-BF16.gguf | head -1)
  ARGS+=(--mmproj "/root/.cache/huggingface${P#"$HF"}")
fi
# shellcheck disable=SC2206
[ -n "${EXTRA:-}" ] && ARGS+=($EXTRA)

docker rm -f "$NAME" >/dev/null 2>&1 || true
trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT INT TERM

(
  until curl -sf "http://127.0.0.1:${PORT}/health" >/dev/null; do sleep 10; done
  docker run --rm --privileged alpine sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'
) &

exec docker run --rm --init --name "$NAME" \
  --device /dev/kfd --device /dev/dri --group-add video --group-add 991 --ipc=host --shm-size 8g \
  -e HF_HUB_OFFLINE=1 -e GPU_MAX_HW_QUEUES=1 \
  -v "$HF":/root/.cache/huggingface:ro -p "127.0.0.1:${PORT}:${PORT}" \
  "$IMAGE" \
  -m "$M" --load-mode none --no-host \
  --jinja --reasoning-format deepseek --temp 1.0 --top-p 0.95 \
  -fa on "${ARGS[@]}" \
  --cache-type-k "$KV" --cache-type-v "$KV" --metrics --host 0.0.0.0 \
  -c "$CTX" --parallel "$PARALLEL" -t "$THREADS" -ub "$UB" -b 2048 --port "$PORT"
