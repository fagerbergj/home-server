# Vulkan (RADV), not ROCm: at 90k context the dense 27B decodes 40 vs 32 t/s and
# prefills 623 vs 376 on the same card. Vulkan enumerates the cards in the OPPOSITE
# order to HIP (VK device 0 == the card HIP called 1); pins in llm-swap.yaml use VK order.
FROM ghcr.io/ggml-org/llama.cpp:server-vulkan

ARG TARGETARCH=amd64
ARG LS_VER=226

WORKDIR /app

RUN curl -fsSL \
    "https://github.com/mostlygeek/llama-swap/releases/download/v${LS_VER}/llama-swap_${LS_VER}_linux_${TARGETARCH}.tar.gz" \
    | tar -xz -C /app

ENTRYPOINT ["/app/llama-swap", "-config", "/app/config.yaml", "--listen", ":11436"]
