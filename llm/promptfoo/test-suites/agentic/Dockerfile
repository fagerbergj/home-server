# Agentic-coding eval sandbox: opencode + Go/Python/Node toolchains, run headless
# against llm-swap. The model's write/bash tool calls are confined to this
# container. Provider URL/model/task/mode are passed at runtime via env.
#
# Go base (matches document-pipeline go.mod 1.25.0); Python for the solo
# (large-code) tasks + BugsInPy; Node for future JS tasks.
FROM golang:1.25-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-pip python3-venv nodejs npm \
      curl ca-certificates git bash \
    && rm -rf /var/lib/apt/lists/*

# pytest + the libraries the solo tasks import. Debian's pip is externally
# managed, so install globally with --break-system-packages.
RUN pip3 install --no-cache-dir --break-system-packages pytest aiohttp pygame

# opencode (standalone binary)
RUN curl -fsSL https://opencode.ai/install | bash
ENV PATH="/root/.opencode/bin:${PATH}" \
    SDL_VIDEODRIVER=dummy \
    PYGAME_HIDE_SUPPORT_PROMPT=1 \
    GOTOOLCHAIN=local \
    GOFLAGS=-mod=mod

WORKDIR /work
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
