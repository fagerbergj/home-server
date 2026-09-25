#!/usr/bin/env bash
# MiMo-V2.6-Flash launcher for llama-swap: llama.cpp (jaison/llm/mimo image), MXFP4 across all four
# cards with the first N expert layers in host RAM, TrevorJS DFlash drafter, vision/audio projector, 4 slots x 128k.
# The weights are read without mmap (the 167 GB file cannot share 126 GB of RAM with 60 GB of resident
# experts), which leaves the page cache full of the file; kswapd then stalls the CPU experts on every
# token (14 vs 42 t/s measured), so a background job drops the cache once the server is healthy.
set -euo pipefail

NAME="${NAME:-mimo}"
PORT="${PORT:-9994}"
IMAGE="${IMAGE:-llama-mimo:gfx1201}"
HF="${HF:-/mnt/cache/huggingface}"
NCMOE="${NCMOE:-23}"   # 23rd CPU layer sits on card 0 and frees the room the projector needs
CTX="${CTX:-524288}"
PARALLEL="${PARALLEL:-4}"
THREADS="${THREADS:-24}"

S=/root/.cache/huggingface/hub/models--ggml-org--MiMo-V2.6-Flash-RL-GGUF/snapshots/9bf2e45b30eb518326536a7f9703bc1bc9b49d06
D=/root/.cache/huggingface/hub/models--TrevorJS--MiMo-V2.6-Flash-RL-GGUF/snapshots/dce9d8c8e576159b1e21c849b494fd1e4e550da2

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
  -m "$S/MiMo-V2.6-Flash-RL-MXFP4-00001-of-00002.gguf" --load-mode none \
  --mmproj "$S/mmproj-MiMo-V2.6-Flash-RL-Q8_0.gguf" \
  -md "$D/MiMo-V2.6-Flash-RL-DFlash-Q8_0.gguf" --spec-type draft-dflash --spec-draft-n-max 5 --spec-draft-p-min 0.7 \
  --jinja --reasoning-format deepseek --temp 1.0 --top-p 0.95 \
  -fa on -ngl 999 --n-cpu-moe "$NCMOE" -ts 24,8,8,8 \
  --cache-type-k f16 --cache-type-v f16 --metrics --host 0.0.0.0 \
  -c "$CTX" --parallel "$PARALLEL" -t "$THREADS" -ub 1024 -b 2048 --port "$PORT"
