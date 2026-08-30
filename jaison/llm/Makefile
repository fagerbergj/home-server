.PHONY: up down images mtp-image

up: images
	docker compose up -d --build llm-swap

down:
	docker compose stop llm-swap
	-docker stop qwen38-27b-vllm flash-next omni muse 2>/dev/null

images: mtp-image
	docker pull ghcr.io/ggml-org/llama.cpp:server-vulkan
	docker pull docker.io/stilldeadcode/vllm-radiance:0.9.3

# Flash-Next MTP fork; rebuild only when Dockerfile/patch change.
mtp-image:
	docker build -t llama-mtp:gfx1201 mtp
