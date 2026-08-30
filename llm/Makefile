.PHONY: swap-up swap-down mtp-image images media-up

# jaison: router + the runtime images it launches
swap-up: images
	docker compose --profile swap up -d --build llm-swap

swap-down:
	docker compose --profile swap stop llm-swap
	-docker stop qwen38-27b-vllm flash-next omni muse 2>/dev/null

images: mtp-image
	docker pull ghcr.io/ggml-org/llama.cpp:server-vulkan
	docker pull docker.io/stilldeadcode/vllm-radiance:0.9.3

# Flash-Next MTP fork (llm/mtp); rebuild only when the Dockerfile/patch change.
mtp-image:
	docker build -t llama-mtp:gfx1201 mtp

# jason-server: llm-swap-media (3090: embed + 9B, peers to jaison) + qdrant + open-webui
media-up:
	docker compose --profile media up -d --build
