# Media-box llama-swap on the RTX 3090 (CUDA): serves Clef locally and peers to
# jaison's llama-swap for everything else (llm-swap-media.yaml).
# Pinned: clef needs build >= 11371 (#29831), and server-cuda floats.
FROM ghcr.io/ggml-org/llama.cpp:server-cuda-b11429@sha256:883915ea20a4b350e98f7284098f4d400c21e9b366e248d397cd42d90602a84c

ARG TARGETARCH=amd64
ARG LS_VER=252

WORKDIR /app

RUN curl -fsSL \
    "https://github.com/mostlygeek/llama-swap/releases/download/v${LS_VER}/llama-swap_${LS_VER}_linux_${TARGETARCH}.tar.gz" \
    | tar -xz -C /app

ENTRYPOINT ["/app/llama-swap", "-config", "/app/config.yaml", "--listen", ":11436"]
