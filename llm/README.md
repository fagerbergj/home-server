# Local LLM (llm-swap + llama.cpp)

OpenAI-compatible LLM gateway backed by [llama-swap](https://github.com/mostlygeek/llama-swap) routing to per-model [llama.cpp](https://github.com/ggml-org/llama.cpp) `llama-server` instances. ROCm-accelerated on 2× AMD Radeon AI Pro R9700 (64 GB VRAM total). [Open WebUI](https://github.com/open-webui/open-webui) provides the chat interface; document-pipeline and OpenCode talk to the API directly.

## Access

Open WebUI:
- LAN: `http://192.168.50.186:3000`
- Public: `https://llm.jasonfagerberg.duckdns.org`

OpenAI-compatible API (tailnet-only — see [networking/setup.md](../networking/setup.md) Phase 7):
- LAN: `http://192.168.50.186:11436/v1`
- Tailnet: `http://jason-server:11436/v1`

## How llm-swap works

`llm-swap.yaml` declares a set of named models. Each model entry has a `cmd` that runs `llama-server` with the model-specific flags (GGUF, context size, KV quant, tensor split, etc.) on the same internal port. When a request hits `/v1/chat/completions` with `model: foo`, llm-swap starts `foo`'s `llama-server` if it isn't already running, waits for the health check, and forwards the request. Models in the same `group` swap each other out so only one chat model is resident at a time. Models in a `persistent` group stay loaded forever (used for the embedding model).

To change which models are available, edit `llm-swap.yaml` and restart the container. See the existing entries for the flag patterns we rely on (`--jinja` for tool calls, `--no-mmap` on 65 GB+ models, `--split-mode tensor` for multi-GPU, `--cache-type-k/v q8_0` where the architecture supports it).

## Current model lineup

| Key in `llm-swap.yaml` | GGUF | Notes |
|---|---|---|
| `qwen3.8-27b` | `unsloth/Qwen3.8-27B-GGUF:UD-Q4_K_XL` | Primary worker (quack orchestrator/researcher/coder). Dense 27 B hybrid Gated-DeltaNet/Attention with native vision. MTP self-speculative decoding (`--spec-type draft-mtp`) roughly doubles decode. 256 K context. |
| `qwen3.6-35b` | `unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q5_K_XL` | Previous primary chat model, kept as an A/B compare partner. |
| `gemma4-26b-a4b` | `unsloth/gemma-4-26B-A4B-it-GGUF:UD-Q4_K_XL` | Live quack judge (26 B MoE, ~4 B active). `-ncmoe 8` keeps it ~15 GB so it co-resides with a worker. |
| `qwen3.5-9b` | `unsloth/Qwen3.5-9B-GGUF:UD-Q4_K_XL` | Small/fast model for cheap requests and eval baselines. |
| `qwen3-vl-32b` | `unsloth/Qwen3-VL-32B-Instruct-GGUF:UD-Q4_K_XL` | Dense-OCR / handwriting vision model (mmproj-F32 via --mmproj-url). |
| `qwen3-omni-30b` | `ggml-org/Qwen3-Omni-30B-A3B-Instruct-GGUF:Q4_K_M` | Media reader — native image + audio. |
| `muse-glimmer-30b` | `unsloth/Muse-Glimmer-30B-GGUF:UD-Q4_K_XL` | Dense 30 B candidate, no set membership until it passes eval. |
| `qwen3-embed` | `Qwen/Qwen3-Embedding-4B-GGUF:Q8_0` | Embeddings, CPU-only and always resident (`ttl: 0`) so it never competes for VRAM. |

## Pre-pulling models

First request to a never-pulled model blocks while llama-server downloads the GGUF (can take minutes for the 65 GB ones). To warm the cache up front:

```bash
./download-models.sh   # every model in the lineup above
```

GGUFs land in `/mnt/cache/huggingface/`. Re-runs are cheap (HF cache dedupes).

## API

```bash
# Chat (streaming or not)
curl http://192.168.50.186:11436/v1/chat/completions \
  -H 'content-type: application/json' \
  -d '{"model": "qwen3.8-27b", "messages": [{"role": "user", "content": "Hello!"}]}'

# Embeddings
curl http://192.168.50.186:11436/v1/embeddings \
  -H 'content-type: application/json' \
  -d '{"model": "qwen3-embed", "input": "some text"}'

# List loaded/declared models
curl http://192.168.50.186:11436/v1/models
```

From outside the home network — connect via Tailscale, then any OpenAI-compatible client works against `http://jason-server:11436/v1`. llm-swap doesn't authenticate; tailnet membership is the access boundary.

## Notes on the stack

- **`--jinja`** is set on every chat model so llama-server uses the embedded chat template for tool calls. Without it, `tools` parameters are silently ignored.
- **`--no-mmap`** is critical on 65 GB+ models — mmap'd reads page-fault serially on a single thread, turning a 1-minute load into 30+ minutes. Direct sequential reads load 65 GB in well under a minute. Cost: full-model RSS during load and no warm-restart page cache.
- **`--cache-type-k/v q8_0`** halves KV cache VRAM but is incompatible with hybrid DeltaNet/Attention models (qwen3-coder-next segfaults). Only enable where the architecture supports it.
- **Tool-call regressions on Llama 3.x**: long tool descriptions push the model to emit `{type, name, parameters}` JSON without the `<|python_tag|>` prefix; llama.cpp's parser then 500s (see PRs ggml-org/llama.cpp#20800, #20806). Workaround: `--skip-chat-parsing` returns the raw JSON in `content` and the client parses it. We don't currently ship a Llama 3.x model — qwen3.x and gpt-oss are clean here.

## Evaluating models

The promptfoo harness under [promptfoo/](promptfoo/) still exists but is dormant —
its Selene judges were retired from `llm-swap.yaml`, so its suites won't run
as-written. Evaluation is moving to [Langfuse](../langfuse/), which ingests
quack's real OTLP traces and turns them into eval datasets; see
`monitoring/otel-collector/config.yaml` for the trace fan-out.

## Updating

```bash
docker compose pull
docker compose build llm-swap
docker compose up -d
```

## Resource notes

- Two llama-swaps: `llm-swap-media` on the media server's RTX 3090 (`make media-up`; embedder + 9B resident, `peers:` to jaison for the rest, `llm-swap-media.yaml`) is the endpoint everything uses; Traefik's public `/openai` route is `api/traefik/dynamic/llm.yml`. On `jaison` (2× R9700, `make swap-up`) a single `llm-swap` router launches each model as a sibling container over the Docker socket (`llm-swap.yaml`): the 27B on vLLM (TP=2 across both cards, int4 AutoRound + DFlash2 draft, 262k context, one id with a `qwen3.8-27b-judge` alias, resident), Flash-Next on the llama.cpp MTP fork (`llm/mtp`, whole box, swaps the 27B out and back), omni and muse on upstream Vulkan llama.cpp.
- Why vLLM for the 27B: at a 90k prompt it prefills 2455 t/s and decodes 106 t/s on TP=2 (two concurrent streams 74 + 62), against 650 / 39 for llama.cpp with DFlash2 on one card. Layer-splitting the dense model in llama.cpp measured 12-16 t/s, so TP only pays under vLLM.
- HuggingFace cache lives on `/mnt/cache/huggingface/` on jaison's NVMe (working set); the archive is the media pool's `/mnt/media/models/huggingface`.
