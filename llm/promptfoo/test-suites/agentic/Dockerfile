# Agentic-coding eval sandbox: opencode + a Python toolchain, run headless
# against llm-swap. The model's write/bash tool calls are confined to this
# container. Provider URL/model/task are passed at runtime via env.
FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl ca-certificates git bash \
    && rm -rf /var/lib/apt/lists/*

# pytest + the libraries the large-code tasks import
RUN pip install --no-cache-dir pytest aiohttp pygame

# opencode (standalone binary)
RUN curl -fsSL https://opencode.ai/install | bash
ENV PATH="/root/.opencode/bin:${PATH}" \
    SDL_VIDEODRIVER=dummy \
    PYGAME_HIDE_SUPPORT_PROMPT=1

WORKDIR /work
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
