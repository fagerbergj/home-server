# jaison's router: llama-swap alone, driving the per-model runtimes as sibling containers over the Docker socket (llama.cpp Vulkan/ROCm, the MTP fork, vLLM). One instance owns both cards, so groups can swap the 27B against Flash-Next.
FROM docker:cli

ARG TARGETARCH=amd64
ARG LS_VER=252

RUN apk add --no-cache bash curl python3

WORKDIR /app
RUN curl -fsSL \
    "https://github.com/mostlygeek/llama-swap/releases/download/v${LS_VER}/llama-swap_${LS_VER}_linux_${TARGETARCH}.tar.gz" \
    | tar -xz -C /app

# Router restarts orphan the fixed-name runtime containers; sweep them first.
COPY entrypoint.sh /app/entrypoint.sh
ENTRYPOINT ["/app/entrypoint.sh"]
