#!/usr/bin/env bash
# Tencent Hy4-flash on vLLM ROCm (4x R9700 32GB TP4 + 123GB RAM):
# Stream-quantized checkpoint (W4A16 symmetric INT4 group-128 routed experts ~76.6 GB +
# BF16 dense/attn/vision/DFly ~19 GB in VRAM; FP8 Engram tables ~64.7 GB in pinned RAM).
# Image: vllm-hy4:rocm (vllm-openai-rocm:nightly + PR #68839 AMD overlay + gfx1201 unlock).
# Escape hatches for Gate 3 bringup: NO_SPEC=1 (disable DFly), NO_MM=1 (text-only),
# ENFORCE_EAGER=1 (skip cudagraphs), RUST_FRONTEND=0 (Python multimodal processor).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="${NAME:-hy4-vllm}"
PORT="${PORT:-9989}"
IMAGE="${IMAGE:-vllm-hy4:rocm}"
MODEL_DIR="${MODEL_DIR:-/mnt/cache/huggingface/hub/hy4-flash-vllm-w4a16}"
CACHE_DIR="${CACHE_DIR:-/mnt/cache/vllm/cache-hy4}"
MOE_CFG="${MOE_CFG:-$SCRIPT_DIR/hy4-moe-r9700.json}"
MOE_CFG_DST="/usr/local/lib/python3.14/dist-packages/vllm/model_executor/layers/fused_moe/configs/E=512,N=384,device_name=AMD_Radeon_R9700,dtype=int4_w4a16.json"
SERVED="${SERVED:-hy4-vllm}"
GPU="${GPU:-0,1,2,3}"
TP="${TP:-4}"
MAXLEN="${MAXLEN:-131072}"
MAXSEQS="${MAXSEQS:-6}"
BATCHTOK="${BATCHTOK:-1024}"
GPUUTIL="${GPUUTIL:-0.92}"
KV_DTYPE="${KV_DTYPE:-auto}"
SPEC_TOKENS="${SPEC_TOKENS:-5}"
RUST_FRONTEND="${RUST_FRONTEND:-1}"
# Default NO_MM=1: profiling a max-resolution 4,914-token image in encoder_runner spikes >9 GiB
# transient VRAM on top of the 22.3 GiB weights and OOMs a 32 GiB R9700. Set NO_MM=0 to override.
NO_MM="${NO_MM:-1}"

if [[ ! -f "$MODEL_DIR/config.json" ]]; then
  echo "FATAL: $MODEL_DIR/config.json missing — run quant-hy4-vllm.py first" >&2
  exit 2
fi

ARGS=(
  /model
  --served-model-name "$SERVED"
  --dtype bfloat16
  --tensor-parallel-size "$TP"
  --gpu-memory-utilization "$GPUUTIL"
  --kv-cache-dtype "$KV_DTYPE"
  --max-model-len "$MAXLEN"
  --max-num-seqs "$MAXSEQS"
  --max-num-batched-tokens "$BATCHTOK"
  --enable-prefix-caching
  --enable-auto-tool-choice
  --tool-call-parser hy_v4
  --reasoning-parser hy_v4
  --host 0.0.0.0 --port 8000
)

if [[ "${NO_MM:-0}" == "1" ]]; then
  ARGS+=(--limit-mm-per-prompt '{"image":0,"video":0}')
else
  ARGS+=(--limit-mm-per-prompt '{"image":1,"video":0}')
fi

if [[ "${NO_SPEC:-0}" != "1" ]]; then
  ARGS+=(--speculative-config "{\"num_speculative_tokens\":${SPEC_TOKENS},\"method\":\"dfly\"}")
fi

[[ "${ENFORCE_EAGER:-0}" == "1" ]] && ARGS+=(--enforce-eager)
[[ -n "${PROF_DIR:-}" ]] && ARGS+=(--profiler-config "{\"profiler\":\"torch\",\"torch_profiler_dir\":\"${PROF_DIR}\",\"torch_profiler_dump_cuda_time_total\":true}")
# Splitting $EXTRA into separate CLI flags is intentional.
# shellcheck disable=SC2206
[[ -n "${EXTRA:-}" ]] && ARGS+=($EXTRA)

MOE_MOUNT=()
[[ -f "$MOE_CFG" ]] && MOE_MOUNT=(-v "$MOE_CFG:${MOE_CFG_DST}:ro")

[[ -d "$CACHE_DIR" ]] || mkdir -p "$CACHE_DIR"
docker rm -f "$NAME" >/dev/null 2>&1 || true
trap 'docker logs "$NAME" > /tmp/hy4-vllm-last.log 2>&1 || true; docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT INT TERM

docker run --init --name "$NAME" --no-healthcheck \
  --device /dev/kfd --device /dev/dri \
  --group-add video --group-add 991 \
  --ipc=host --shm-size 8g --cap-add SYS_PTRACE --security-opt seccomp=unconfined \
  -v "$MODEL_DIR:/model:ro" \
  -v "$CACHE_DIR:/cache" \
  "${MOE_MOUNT[@]}" \
  -p "127.0.0.1:${PORT}:8000" \
  -e HIP_VISIBLE_DEVICES="$GPU" \
  -e NCCL_P2P_DISABLE="${NCCL_P2P_DISABLE:-1}" \
  -e PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
  -e TRITON_CACHE_AUTOTUNING=1 \
  -e HF_HUB_OFFLINE=1 \
  -e VLLM_USE_RUST_FRONTEND="$RUST_FRONTEND" \
  -e VLLM_ROCM_USE_AITER=1 \
  -e VLLM_ROCM_USE_AITER_TRITON_SPARSE_MLA=1 \
  -e VLLM_ROCM_USE_AITER_LINEAR=0 \
  -e VLLM_ROCM_USE_AITER_FP8BMM=0 \
  -e VLLM_CACHE_ROOT=/cache/vllm \
  -e TORCHINDUCTOR_CACHE_DIR=/cache/inductor \
  -e TRITON_CACHE_DIR=/cache/triton \
  -e AITER_ROOT_DIR=/cache/aiter \
  "$IMAGE" "${ARGS[@]}"
