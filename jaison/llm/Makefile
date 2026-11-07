.PHONY: up down images mtp-image glm-image

up: images
	docker compose up -d --build llm-swap

down:
	docker compose stop llm-swap
	-docker stop qwen38-27b-vllm flash-next mimo glm omni muse embed 2>/dev/null

images: mtp-image glm-image
	docker pull ghcr.io/ggml-org/llama.cpp:server-vulkan
	docker pull ghcr.io/ggml-org/llama.cpp:server-b11371
	docker pull ghcr.io/ggml-org/llama.cpp:server-rocm-b12110
	docker pull docker.io/stilldeadcode/vllm-radiance:0.9.3

# llama.cpp + a model's patch series (upstream/patched.Dockerfile); ccache shares ggml-hip between them.
# Flash-Next rides the newest stock base (dry-run the mtp4 patches on the new tree first); GLM stays on b11580,
# where glm/patches was rebased.
MTP_COMMIT ?= cd959bae99ff4bed22bef2604f45241c09bbb8c8
MTP_BASE ?= b12110
# The llama.patches label records each patch's sha256 prefix, so `docker inspect` shows what an image carries.
patch_sha = $(shell cd $(1) && for p in $$(ls *.patch | head -n $(or $(2),99)); do printf '%s=%s,' "$${p%%-*}" "$$(sha256sum $$p | cut -c1-12)"; done)
mtp-image:
	docker build -f upstream/patched.Dockerfile --build-arg LLAMA_COMMIT=$(MTP_COMMIT) --build-arg PATCHES=mtp4/patches --build-arg NPATCH=1 --build-arg PATCH_SHA=$(call patch_sha,mtp4/patches,1) -t llama-mtp4:$(MTP_BASE)-port .

glm-image:
	docker build -f upstream/patched.Dockerfile --build-arg PATCHES=glm/patches --build-arg PATCH_SHA=$(call patch_sha,glm/patches) -t llama-glm:b11580-p1 .
