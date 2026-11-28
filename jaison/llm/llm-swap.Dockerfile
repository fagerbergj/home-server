# jaison's router: llama-swap alone, driving the per-model runtimes as sibling containers over the Docker socket (llama.cpp Vulkan/ROCm, the MTP fork, vLLM). One instance owns both cards, so groups can swap the 27B against Flash-Next.
FROM docker:cli

ARG TARGETARCH=amd64
ARG LS_VER=252
ARG LS_SHA256=32aea60b5c1be987c27dde6ea4aaa84f9be7ad93eaede011295fad1e276e80ea

RUN apk add --no-cache bash curl python3

WORKDIR /app
RUN curl -fsSL \
    "https://github.com/mostlygeek/llama-swap/releases/download/v${LS_VER}/llama-swap_${LS_VER}_linux_${TARGETARCH}.tar.gz" \
    | tar -xz -C /app \
 && if [ "${TARGETARCH}" = "amd64" ]; then echo "${LS_SHA256}  /app/llama-swap" | sha256sum -c -; fi

# Router restarts orphan the fixed-name runtime containers; sweep them first.
COPY entrypoint.sh /app/entrypoint.sh
ENTRYPOINT ["/app/entrypoint.sh"]
