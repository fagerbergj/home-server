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

# Force-remove our download container on exit/interrupt. `docker run` without a
# TTY doesn't forward Ctrl+C — a killed CLI otherwise leaves the container
# running detached (the orphan pileup). --name (below) makes it findable.
_dlname="hfdl-$$"
_cleanup_dl() { docker rm -f "$_dlname" >/dev/null 2>&1 || true; }
trap _cleanup_dl EXIT
trap '_cleanup_dl; exit 130' INT TERM

# Default set = the GGUFs llm-swap.yaml loads, as file URLs (paste-from-HF).
DEFAULTS=(
  "https://huggingface.co/ggml-org/gpt-oss-120b-GGUF/blob/main/gpt-oss-120b-mxfp4-00001-of-00003.gguf"
  "https://huggingface.co/ggml-org/gpt-oss-120b-GGUF/blob/main/gpt-oss-120b-mxfp4-00002-of-00003.gguf"
  "https://huggingface.co/ggml-org/gpt-oss-120b-GGUF/blob/main/gpt-oss-120b-mxfp4-00003-of-00003.gguf"
  "https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF/blob/main/Qwen3.6-35B-A3B-UD-Q5_K_XL.gguf"
  "https://huggingface.co/unsloth/Qwen3-Coder-Next-GGUF/blob/main/Qwen3-Coder-Next-UD-Q4_K_XL.gguf"
  "https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/blob/main/Qwen3.5-9B-UD-Q4_K_XL.gguf"
  "https://huggingface.co/unsloth/Qwen3-VL-32B-Instruct-GGUF/blob/main/Qwen3-VL-32B-Instruct-UD-Q4_K_XL.gguf"
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

  # Disk guard: skip if free space < file size + 10GB buffer. (Already-cached
  # files re-download to nothing, but we check before pulling anyway.)
  local resolve size free buffer=$((10 * 1024 * 1024 * 1024))
  resolve="https://huggingface.co/$repo/resolve/main/$file"
  size="$(curl -sIL "$resolve" 2>/dev/null | awk 'tolower($1)=="content-length:"{n=$2} END{gsub(/[^0-9]/,"",n); print n}')" || true
  case "$size" in ''|*[!0-9]*) size= ;; esac
  free="$(df -P -B1 "$HF_CACHE" | awk 'NR==2{print $4}')"
  if [ -n "$size" ] && [ "$((size + buffer))" -gt "$free" ]; then
    echo "!! SKIP $file — need $((size / 1024 / 1024 / 1024))GB + 10GB buffer, only $((free / 1024 / 1024 / 1024))GB free" >&2
    return 1
  fi

  echo "── $repo : $file ($(( ${size:-0} / 1024 / 1024 / 1024 ))GB)"
  docker run --rm --name "$_dlname" \
    -e HUGGING_FACE_HUB_TOKEN="${HF_TOKEN:-}" \
    -v "$HF_CACHE:/root/.cache/huggingface" \
    python:3.12-slim \
    sh -c "pip install -q huggingface_hub && hf download '$repo' '$file'"
  echo ""
}

urls=("$@")
[ "${#urls[@]}" -eq 0 ] && urls=("${DEFAULTS[@]}")
for u in "${urls[@]}"; do dl "$u" || echo "  (skipped: $u)"; done
echo "All done."
