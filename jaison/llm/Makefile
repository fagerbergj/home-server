.PHONY: up down images mtp-image glm-image

up: images
	docker compose up -d --build llm-swap

down:
	docker compose stop llm-swap
	-docker stop qwen38-27b-vllm flash-next mimo glm omni muse embed 2>/dev/null

images: mtp-image glm-image
	docker pull ghcr.io/ggml-org/llama.cpp:server-vulkan
	docker pull ghcr.io/ggml-org/llama.cpp:server-b11371
	docker pull ghcr.io/ggml-org/llama.cpp:server-rocm-b11580
	docker pull docker.io/stilldeadcode/vllm-radiance:0.9.3

# llama.cpp b11580 + a model's patch series (upstream/patched.Dockerfile); ccache shares ggml-hip between them.
# The llama.patches label records each patch's sha256 prefix, so `docker inspect` shows what an image carries.
patch_sha = $(shell cd $(1) && for p in $$(ls *.patch | head -n $(or $(2),99)); do printf '%s=%s,' "$${p%%-*}" "$$(sha256sum $$p | cut -c1-12)"; done)
mtp-image:
	docker build -f upstream/patched.Dockerfile --build-arg PATCHES=mtp4/patches --build-arg NPATCH=1 --build-arg PATCH_SHA=$(call patch_sha,mtp4/patches,1) -t llama-mtp4:b11580-port .

glm-image:
	docker build -f upstream/patched.Dockerfile --build-arg PATCHES=glm/patches --build-arg PATCH_SHA=$(call patch_sha,glm/patches) -t llama-glm:b11580-p1 .
