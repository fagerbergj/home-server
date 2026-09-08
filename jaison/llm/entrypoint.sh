#!/bin/sh
docker stop -t 120 qwen38-27b-vllm flash-next omni muse >/dev/null 2>&1; docker rm -f qwen38-27b-vllm flash-next omni muse >/dev/null 2>&1
exec /app/llama-swap -config /app/config.yaml --listen :11436
