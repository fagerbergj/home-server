# Media-box llama-swap on the RTX 3090 (CUDA): serves Clef locally and peers to
# jaison's llama-swap for everything else (llm-swap-media.yaml).
# Pinned: clef needs build >= 11371 (#29831), and server-cuda floats.
# Bumped b11429 -> b12808 (+12-17% Clef prefill on RTX 3090 with -fa on).
FROM ghcr.io/ggml-org/llama.cpp:server-cuda-b12808@sha256:c94503b4e7839fcacebc7fd04b7cef66376dc15a38e50e221e73871241a12982

ARG TARGETARCH=amd64
ARG LS_VER=252
ARG LS_SHA256=32aea60b5c1be987c27dde6ea4aaa84f9be7ad93eaede011295fad1e276e80ea

WORKDIR /app

RUN curl -fsSL \
    "https://github.com/mostlygeek/llama-swap/releases/download/v${LS_VER}/llama-swap_${LS_VER}_linux_${TARGETARCH}.tar.gz" \
    | tar -xz -C /app \
 && if [ "${TARGETARCH}" = "amd64" ]; then echo "${LS_SHA256}  /app/llama-swap" | sha256sum -c -; fi

ENTRYPOINT ["/app/llama-swap", "-config", "/app/config.yaml", "--listen", ":11436"]
