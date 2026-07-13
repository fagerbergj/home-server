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
  ggml-org/gpt-oss-120b-GGUF gpt-oss-120b-mxfp4-00001-of-00003.gguf
  ggml-org/gpt-oss-120b-GGUF gpt-oss-120b-mxfp4-00002-of-00003.gguf
  ggml-org/gpt-oss-120b-GGUF gpt-oss-120b-mxfp4-00003-of-00003.gguf
  unsloth/Qwen3.6-35B-A3B-GGUF Qwen3.6-35B-A3B-UD-Q5_K_XL.gguf
  unsloth/Qwen3-Coder-Next-GGUF Qwen3-Coder-Next-UD-Q4_K_XL.gguf
  unsloth/Qwen3.5-9B-GGUF Qwen3.5-9B-UD-Q4_K_XL.gguf
  unsloth/Qwen3-VL-32B-Instruct-GGUF Qwen3-VL-32B-Instruct-UD-Q4_K_XL.gguf
  Qwen/Qwen3-Embedding-4B-GGUF Qwen3-Embedding-4B-Q8_0.gguf
  mradermacher/Selene-1-Llama-3.3-70B-i1-GGUF Selene-1-Llama-3.3-70B.i1-Q4_K_M.gguf
  mradermacher/Selene-1-Mini-Llama-3.1-8B-GGUF Selene-1-Mini-Llama-3.1-8B.Q8_0.gguf
  unsloth/gemma-4-26B-A4B-it-GGUF gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf
  unsloth/gemma-4-12b-it-GGUF gemma-4-12b-it-UD-Q6_K_XL.gguf
  ggml-org/Qwen3-Omni-30B-A3B-Instruct-GGUF Qwen3-Omni-30B-A3B-Instruct-Q4_K_M.gguf
  ggml-org/Qwen3-Omni-30B-A3B-Instruct-GGUF mmproj-Qwen3-Omni-30B-A3B-Instruct-bf16.gguf
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
