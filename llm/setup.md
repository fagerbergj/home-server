# LLM — Setup

## 1. (Optional) Pre-pull the model weights

Skips the multi-minute wait on the first request to a model.

```bash
cd ~/workspace/home-server/llm
./download-models.sh
```

Requires `HF_TOKEN` in the environment for gated repos.

## 2. Start services

```bash
docker compose up -d --build llm-swap
docker compose up -d qdrant
```

llm-swap is built locally (`llm-swap.Dockerfile`); the build is fast after the first run because the base image is cached.

## 3. Verify llm-swap

```bash
# List declared models
curl -s http://192.168.50.186:11436/v1/models | jq .

# Round-trip a small chat request — this also kicks off the first load
# of the named model, so the response can take a minute or two.
curl http://192.168.50.186:11436/v1/chat/completions \
  -H 'content-type: application/json' \
  -d '{"model": "qwen3.8-27b", "messages": [{"role": "user", "content": "say hello"}], "max_tokens": 10}'

# Confirm GPU usage during a request (on the AI box)
rocm-smi --showuse
```

## 4. Verify tailnet access

From any tailnet-enrolled device:

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://jason-server:11436/v1/models
```

Should return `200`. From a non-tailnet device on the public internet the request should fail outright — that's the access boundary working.

## Adding or swapping a model

1. Edit `llm-swap.yaml` — add a new key under `models:` with its `cmd: > /app/llama-server ...` line. Mirror an existing entry for the flag pattern (`--jinja`, `--no-mmap`, `--split-mode tensor`, etc.).
2. (Optional) Add to the `main` or `embed` group depending on swap semantics.
3. Pre-pull the GGUF: `./download-models.sh` (edit the script to add the new model first).
4. `docker compose restart llm-swap`.
