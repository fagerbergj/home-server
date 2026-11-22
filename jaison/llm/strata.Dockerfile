# Minimal runtime image for Strata's OpenAI/Anthropic server (terminal/serve/server.py).
# Engine binaries, DFlash2 pack, tokenizer, and weights are bind-mounted from /mnt/cache.
FROM python:3.14-slim
RUN apt-get update && apt-get install -y --no-install-recommends libgomp1 libstdc++6 curl \
 && rm -rf /var/lib/apt/lists/* \
 && pip install --no-cache-dir fastapi uvicorn tokenizers httpx pillow numpy jinja2 psutil pyyaml regex
