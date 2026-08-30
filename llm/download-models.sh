#!/usr/bin/env bash
# Pre-download model GGUFs into the HF cache so the first llm-swap load is instant.
# Uses `hf download` (the official huggingface_hub CLI) so files land in the
# standard HF cache layout that llama.cpp's -hf flag reads directly.
#
#   ./download-models.sh                       # download the default llm-swap set
#   ./download-models.sh <repo> <file> ...     # download specific repo/file pairs
set -euo pipefail

HF_CACHE=/mnt/cache/huggingface

# repo/file pairs for every GGUF llm-swap.yaml loads via -hf.
DEFAULTS=(
  unsloth/Qwen3.6-35B-A3B-GGUF Qwen3.6-35B-A3B-UD-Q5_K_XL.gguf
  unsloth/Qwen3.8-27B-GGUF Qwen3.8-27B-UD-Q4_K_XL.gguf
  unsloth/Qwen3.8-27B-GGUF mmproj-BF16.gguf
  unsloth/Qwen3.5-9B-GGUF Qwen3.5-9B-UD-Q4_K_XL.gguf
  unsloth/Qwen3-VL-32B-Instruct-GGUF Qwen3-VL-32B-Instruct-UD-Q4_K_XL.gguf
  Qwen/Qwen3-Embedding-4B-GGUF Qwen3-Embedding-4B-Q8_0.gguf
  unsloth/gemma-4-26B-A4B-it-GGUF gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf
  ggml-org/Qwen3-Omni-30B-A3B-Instruct-GGUF Qwen3-Omni-30B-A3B-Instruct-Q4_K_M.gguf
  ggml-org/Qwen3-Omni-30B-A3B-Instruct-GGUF mmproj-Qwen3-Omni-30B-A3B-Instruct-bf16.gguf
  unsloth/Muse-Glimmer-30B-GGUF Muse-Glimmer-30B-UD-Q4_K_XL.gguf
  unsloth/Muse-Glimmer-30B-GGUF mmproj-Muse-Glimmer-30B-Q8_0.gguf
)

args=("$@")
[ "${#args[@]}" -eq 0 ] && args=("${DEFAULTS[@]}")
[ $(( ${#args[@]} % 2 )) -eq 0 ] || { echo "expected pairs of <repo> <file>" >&2; exit 1; }

docker run --rm \
  -e HUGGING_FACE_HUB_TOKEN="${HF_TOKEN:-}" \
  -v "$HF_CACHE:/root/.cache/huggingface" \
  python:3.12-slim \
  bash -c '
    pip install -q -U "huggingface_hub[cli]"
    while [ "$#" -gt 0 ]; do
      echo "── $1 : $2"
      hf download "$1" "$2" || echo "  (failed: $1 $2)"
      shift 2
    done
  ' _ "${args[@]}"
echo "All done."
