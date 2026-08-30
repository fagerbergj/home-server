# jaison's ROCm llama-swap (llm-swap-rocm.yaml): Flash-Next prefills 2x faster on HIP
# than on the Vulkan image the main llm-swap uses. One binary per container, so two.
FROM ghcr.io/ggml-org/llama.cpp:server-rocm

ARG TARGETARCH=amd64
ARG LS_VER=226

WORKDIR /app

RUN curl -fsSL \
    "https://github.com/mostlygeek/llama-swap/releases/download/v${LS_VER}/llama-swap_${LS_VER}_linux_${TARGETARCH}.tar.gz" \
    | tar -xz -C /app

ENTRYPOINT ["/app/llama-swap", "-config", "/app/config.yaml", "--listen", ":11437"]
