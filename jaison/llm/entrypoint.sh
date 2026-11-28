#!/bin/sh
CONTAINERS="qwen38-27b-vllm flash-next glm deepseek hy4 hy4-vllm embed mimo omni muse inkling"
# shellcheck disable=SC2086
docker stop -t 120 $CONTAINERS >/dev/null 2>&1
# shellcheck disable=SC2086
docker rm -f $CONTAINERS >/dev/null 2>&1
exec /app/llama-swap -config /app/config.yaml --listen :11436
