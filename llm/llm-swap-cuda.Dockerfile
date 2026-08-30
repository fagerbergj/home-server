# Media-box llama-swap on the RTX 3090 (CUDA): serves the embedder and the 9B
# locally and peers to jaison's llama-swap for everything larger
# (llm-swap-media.yaml). Same llama-swap binary as llm-swap.Dockerfile.
FROM ghcr.io/ggml-org/llama.cpp:server-cuda

ARG TARGETARCH=amd64
ARG LS_VER=226

WORKDIR /app

RUN curl -fsSL \
    "https://github.com/mostlygeek/llama-swap/releases/download/v${LS_VER}/llama-swap_${LS_VER}_linux_${TARGETARCH}.tar.gz" \
    | tar -xz -C /app

ENTRYPOINT ["/app/llama-swap", "-config", "/app/config.yaml", "--listen", ":11436"]
