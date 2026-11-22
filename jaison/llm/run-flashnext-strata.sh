#!/usr/bin/env bash
# Qwen3.8-Flash-Next launcher for llama-swap via Strata v0.2.19 (strata-split-4-amd + DFlash2 + GPU Vision).
# 4x Radeon AI PRO R9700 (gfx1201) all-cards split: Unsloth UD-Q4_K_XL experts in VRAM (~26 GiB/card),
# 29.5 GB PLE/embeddings in RAM (~12 GB total RAM used), INT8 KV pool ~416k tokens (262k ctx, 8 lanes) +
# 16 GiB RAM conversation park cache. Measured 2026-11-22: 199.6 tok/s coding decode, 163.9 tok/s tools,
# 167.2 tok/s 4-way concurrent aggregate, 32.6s cold boot.
set -euo pipefail

NAME="${NAME:-flash-next}"
PORT="${PORT:-9994}"
IMAGE="${IMAGE:-strata-server:0.2.19}"
STRATA_DIR="${STRATA_DIR:-/mnt/cache/strata}"
HF="${HF:-/mnt/cache/huggingface}"
MODEL_SUB="${MODEL_SUB:-hub/qwen3.8-flash-next-q4xl}"
MAX_CTX="${MAX_CTX:-262144}"
LANES="${LANES:-8}"
CONV_CACHE_MIB="${CONV_CACHE_MIB:-16384}"

docker rm -f "$NAME" >/dev/null 2>&1 || true
trap 'docker logs "$NAME" > /tmp/flashnext-strata-last.log 2>&1 || true; docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT INT TERM

docker run --init --name "$NAME" --no-healthcheck \
  --device /dev/kfd --device /dev/dri \
  --group-add video --group-add 991 \
  --ipc=host --shm-size 8g \
  -v "$STRATA_DIR":/strata:ro \
  -v "$HF":/root/.cache/huggingface:ro \
  -p "127.0.0.1:${PORT}:${PORT}" \
  -e PYTHONPATH=/strata/repo/terminal \
  -e STRATA_ALLOWED_HOSTS="localhost,127.0.0.1,jaison,llm-swap,192.168.50.202,100.64.0.1" \
  "$IMAGE" bash -c "
cat > /tmp/strata-run.json <<EOF
{
  \"model\": \"qwen3.8-flash-next\",
  \"backend\": \"hip\",
  \"exe\": \"/strata/engine/strata-split-4-amd-dflash2\",
  \"tokenizer\": \"/strata/tok/tokenizer\",
  \"cwd\": \"/strata/engine\",
  \"log\": \"/tmp/strata-engine.log\",
  \"vision\": {
    \"exe\": \"/strata/engine/strata-vision-hip\",
    \"mmproj\": \"/root/.cache/huggingface/${MODEL_SUB}/mmproj-BF16.gguf\",
    \"model\": \"/root/.cache/huggingface/${MODEL_SUB}/Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf\",
    \"gpu\": true
  },
  \"env\": {
    \"LD_LIBRARY_PATH\": \"/strata/engine\",
    \"FNX_ARENA\": \"0\",
    \"FNX_EXPERT_RAM_GIB\": \"off\"
  },
  \"args\": [
    \"--native\", \"/root/.cache/huggingface/${MODEL_SUB}/Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf\",
    \"--draft-vocab\", \"/strata/repo/terminal/data/draft_vocab_en.bin\",
    \"--max-context\", \"${MAX_CTX}\",
    \"--spec\", \"6\",
    \"--lookup\", \"15\",
    \"--conversation-cache-mib\", \"${CONV_CACHE_MIB}\",
    \"--batch\", \"${LANES}\",
    \"--vision\"
  ]
}
EOF
exec python3 /strata/repo/terminal/serve/server.py \
  --engine strata --config /tmp/strata-run.json \
  --host 0.0.0.0 --port ${PORT}
"
