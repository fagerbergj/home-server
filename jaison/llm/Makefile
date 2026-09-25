.PHONY: up down images mtp-image mimo-image glm-image

up: images
	docker compose up -d --build llm-swap

down:
	docker compose stop llm-swap
	-docker stop qwen38-27b-vllm flash-next mimo glm omni muse 2>/dev/null

images: mtp-image
	docker pull ghcr.io/ggml-org/llama.cpp:server-vulkan
	docker pull docker.io/stilldeadcode/vllm-radiance:0.9.3

# Flash-Next image (master + MTP and tensor-split PRs); rebuild only when Dockerfile/diffs change.
mtp-image:
	docker build -t llama-mtp4:gfx1201 mtp4

# Scratch MiMo-V2.6-Flash image: upstream master + RCCL, no patches.
mimo-image:
	docker build -t llama-mimo:gfx1201 mimo

# Scratch GLM-5.3-Flash image: unsloth's PR 27754 branch.
glm-image:
	docker build -t llama-glm:gfx1201 glm
