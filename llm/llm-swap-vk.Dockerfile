# Vulkan llama-swap: qwen3.8-27b only, pinned to GPU1. Dense 27B decodes ~50 t/s on
# Vulkan vs ~40 on HIP (same card, same flags); MoE gemma is 12% SLOWER on Vulkan, so
# everything else stays on the HIP llm-swap. Two containers because the Vulkan image's
# glibc (2.43) is newer than the ROCm image's - the binaries can't share a filesystem.
FROM ghcr.io/ggml-org/llama.cpp:server-vulkan
ARG TARGETARCH=amd64
ARG LS_VER=226
WORKDIR /app
RUN curl -fsSL \
    "https://github.com/mostlygeek/llama-swap/releases/download/v${LS_VER}/llama-swap_${LS_VER}_linux_${TARGETARCH}.tar.gz" \
    | tar -xz -C /app
ENTRYPOINT ["/app/llama-swap", "-config", "/app/config.yaml", "--listen", ":11437"]
