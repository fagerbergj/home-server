.PHONY: up down images strata-image mtp-image glm-image inkling-image

CONTAINERS := qwen38-27b-vllm flash-next glm deepseek hy4 embed mimo omni muse inkling

up: images
	docker compose up -d --build --force-recreate llm-swap

down:
	docker compose stop llm-swap
	-docker stop -t 120 $(CONTAINERS) 2>/dev/null

images: strata-image
	docker pull ghcr.io/ggml-org/llama.cpp:server-b11371
	docker pull docker.io/stilldeadcode/vllm-radiance:0.9.3

strata-image:
	docker build -f strata.Dockerfile -t strata-server:0.2.19 .

# llama.cpp + a model's patch series (upstream/patched.Dockerfile); ccache shares ggml-hip between them.
# Opt-in targets for cold-storage / fallback models; dry-run patches before bumping base commits.
MTP_COMMIT ?= cd959bae99ff4bed22bef2604f45241c09bbb8c8
MTP_BASE ?= b12110
# Stock master at the Inkling 2 Mini merge (29b52d39, PR 32694); inkling2 + its mtmd vision.
INKLING_COMMIT ?= 29b52d398b294509746ec0a3f28948a3107c0213
# The llama.patches label records each patch's sha256 prefix, so `docker inspect` shows what an image carries.
patch_sha = $(shell cd $(1) && for p in $$(ls *.patch | head -n $(or $(2),99)); do printf '%s=%s,' "$${p%%-*}" "$$(sha256sum $$p | cut -c1-12)"; done)
mtp-image:
	docker build -f upstream/patched.Dockerfile --build-arg LLAMA_COMMIT=$(MTP_COMMIT) --build-arg LLAMA_VERSION=$(MTP_BASE) --build-arg PATCHES=mtp4/patches --build-arg NPATCH=1 --build-arg PATCH_SHA=$(call patch_sha,mtp4/patches,1) -t llama-mtp4:$(MTP_BASE)-port .

inkling-image:
	docker build -f upstream/patched.Dockerfile --build-arg LLAMA_COMMIT=$(INKLING_COMMIT) --build-arg LLAMA_VERSION=29b52d39 --build-arg PATCHES=inkling/patches --build-arg NPATCH=0 --build-arg PATCH_SHA=none -t llama-inkling:29b52d39 .

glm-image:
	docker build -f upstream/patched.Dockerfile --build-arg LLAMA_VERSION=b11580 --build-arg PATCHES=glm/patches --build-arg PATCH_SHA=$(call patch_sha,glm/patches) -t llama-glm:b11580-p1 .
