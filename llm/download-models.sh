#!/usr/bin/env bash
# Pre-download model GGUFs into the HF cache so the first llm-swap load is instant.
#
#   ./download-models.sh                      # download the default llm-swap set
#   ./download-models.sh <hf-file-url> ...    # download specific file(s) by URL
#
# A <hf-file-url> is a HuggingFace file page or resolve link — copy it straight
# from the HF "files" tab, e.g.
#   https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF/blob/main/gemma-4-26B-A4B-it-UD-Q4_K_M.gguf
set -euo pipefail

HF_CACHE=/mnt/cache/huggingface

# Default set = the GGUFs llm-swap.yaml loads, as file URLs (paste-from-HF).
DEFAULTS=(
  "https://huggingface.co/unsloth/gpt-oss-120b-GGUF/blob/main/gpt-oss-120b-F16.gguf"
  "https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF/blob/main/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf"
  "https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF/blob/main/gemma-4-26B-A4B-it-UD-Q4_K_M.gguf"
  "https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/blob/main/Qwen3.5-9B-Q4_K_M.gguf"
  "https://huggingface.co/unsloth/Qwen3-VL-8B-Instruct-GGUF/blob/main/Qwen3-VL-8B-Instruct-Q4_K_M.gguf"
  "https://huggingface.co/unsloth/Qwen3-VL-8B-Instruct-GGUF/blob/main/mmproj-F16.gguf"
  "https://huggingface.co/unsloth/Qwen3-Coder-Next-GGUF/blob/main/Qwen3-Coder-Next-UD-Q4_K_M.gguf"
  "https://huggingface.co/Qwen/Qwen3-Embedding-0.6B-GGUF/blob/main/Qwen3-Embedding-0.6B-Q8_0.gguf"
  "https://huggingface.co/mradermacher/Selene-1-Llama-3.3-70B-i1-GGUF/blob/main/Selene-1-Llama-3.3-70B.i1-Q4_K_M.gguf"
)

# Parse "<org>/<repo>/(blob|resolve)/<branch>/<file>" out of a HF URL and download
# that one file. hf download is idempotent — already-cached files are skipped.
dl() {
  local url="$1" path repo file
  path="${url#http*://huggingface.co/}"   # strip scheme + host
  path="${path%%\?*}"                       # strip ?query
  repo="$(printf '%s' "$path" | sed -E 's#/(blob|resolve)/.*##')"
  file="$(printf '%s' "$path" | sed -E 's#^.*/(blob|resolve)/[^/]+/##')"
  if [ -z "$repo" ] || [ -z "$file" ] || [ "$file" = "$path" ]; then
    echo "!! can't parse a repo + file from: $url" >&2
    echo "   expected .../<org>/<repo>/blob/<branch>/<file.gguf>" >&2
    return 1
  fi
  echo "── $repo : $file"
  docker run --rm \
    -e HUGGING_FACE_HUB_TOKEN="${HF_TOKEN:-}" \
    -v "$HF_CACHE:/root/.cache/huggingface" \
    python:3.12-slim \
    sh -c "pip install -q huggingface_hub && hf download '$repo' '$file'"
  echo ""
}

urls=("$@")
[ "${#urls[@]}" -eq 0 ] && urls=("${DEFAULTS[@]}")
for u in "${urls[@]}"; do dl "$u"; done
echo "All done."
