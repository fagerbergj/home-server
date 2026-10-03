# Media-box llama-swap on the RTX 3090 (CUDA): serves Clef locally and peers to
# jaison's llama-swap for everything else (llm-swap-media.yaml).
# Pinned: clef needs build >= 11371 (#29831), and server-cuda floats.
FROM ghcr.io/ggml-org/llama.cpp:server-cuda-b11371@sha256:f90b9de8baf5244c2c43f9594d7522424470f0d472323fe10405eceae714405b

ARG TARGETARCH=amd64
ARG LS_VER=252

WORKDIR /app

RUN curl -fsSL \
    "https://github.com/mostlygeek/llama-swap/releases/download/v${LS_VER}/llama-swap_${LS_VER}_linux_${TARGETARCH}.tar.gz" \
    | tar -xz -C /app

ENTRYPOINT ["/app/llama-swap", "-config", "/app/config.yaml", "--listen", ":11436"]
