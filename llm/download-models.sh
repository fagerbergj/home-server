#!/usr/bin/env bash
# Pre-download all llm-swap model GGUFs to the HF cache.
# Run before starting llm-swap so the first model load is instant.
# Usage: ./download-models.sh [--judge]

set -euo pipefail

HF_CACHE=/mnt/cache/huggingface

dl() {
  local repo="$1" file="$2" label="$3"
  echo "── $label"
  docker run --rm \
    -e HUGGING_FACE_HUB_TOKEN="${HF_TOKEN:-}" \
    -v "$HF_CACHE:/root/.cache/huggingface" \
    python:3.12-slim \
    sh -c "pip install -q 'huggingface_hub[cli]' && huggingface-cli download '$repo' '$file'"
  echo ""
}

dl "unsloth/Llama-3.3-70B-Instruct-GGUF"   "Llama-3.3-70B-Instruct-Q4_K_M.gguf"  "llama-3.3-70b"
dl "unsloth/Qwen3.6-35B-A3B-GGUF"          "Qwen3.6-35B-A3B-UD-Q4_K_M.gguf"      "qwen3.6-35b"
dl "unsloth/Qwen3.5-9B-GGUF"               "Qwen3.5-9B-Q4_K_M.gguf"              "qwen3.5-9b"
dl "unsloth/Qwen3-VL-8B-Instruct-GGUF"     "Qwen3-VL-8B-Instruct-Q4_K_M.gguf"   "qwen3-vl-8b"
dl "unsloth/Qwen3-VL-8B-Instruct-GGUF"     "mmproj-F16.gguf"                     "qwen3-vl-8b mmproj"
dl "unsloth/Qwen3-Coder-Next-GGUF"         "Qwen3-Coder-Next-Q4_K_M.gguf"        "qwen3-coder-next"
dl "Qwen/Qwen3-Embedding-0.6B-GGUF"        "Qwen3-Embedding-0.6B-Q8_0.gguf"      "qwen3-embed"

if [[ "${1:-}" == "--judge" ]]; then
  dl "prometheus-eval/prometheus-7b-v2.0-GGUF" "prometheus-7b-v2.0.Q4_K_M.gguf" "prometheus-7b (judge)"
fi

echo "All done. Run 'make swap-up' to start."
