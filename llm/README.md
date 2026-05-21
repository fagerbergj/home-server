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
| `gpt-oss-120b` | `unsloth/gpt-oss-120b-GGUF:F16` (MXFP4 native) | Primary chat model. Modern tool-call template, ~5 B active of 120 B total. Tensor-split across both GPUs. |
| `qwen3.6-35b` | `unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q4_K_M` | Proven middle-tier chat model + A/B compare partner for evals. |
| `qwen3-coder-next` | `unsloth/Qwen3-Coder-Next-GGUF:Q4_K_M` | Code specialist (80 B MoE, 3 B active). Hybrid DeltaNet/Attention — do not set KV quant. 256 K context. |
| `qwen3.5-9b` | `unsloth/Qwen3.5-9B-GGUF:Q4_K_M` | Small/fast model for cheap requests and eval baselines. |
| `qwen3-vl-8b` | `unsloth/Qwen3-VL-8B-Instruct-GGUF:Q4_K_M` | Vision model used by document-pipeline OCR. |
| `qwen3-embed` | `Qwen/Qwen3-Embedding-0.6B-GGUF:Q8_0` | Persistent embedding model on CPU. Stays loaded. |

## Pre-pulling models

First request to a never-pulled model blocks while llama-server downloads the GGUF (can take minutes for the 65 GB ones). To warm the cache up front:

```bash
./download-models.sh   # all models incl. the Selene judge
```

GGUFs land in `/mnt/cache/huggingface/`. Re-runs are cheap (HF cache dedupes).

## API

```bash
# Chat (streaming or not)
curl http://192.168.50.186:11436/v1/chat/completions \
  -H 'content-type: application/json' \
  -d '{"model": "gpt-oss-120b", "messages": [{"role": "user", "content": "Hello!"}]}'

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

See [promptfoo/README.md](promptfoo/README.md) for the eval harness. Suites cover architecture/coding/math/tool-calls/large-code.

The judge is `selene` — Atla Selene-1 70B, a GPU model inside llm-swap (port 11436), used for both per-model rubric grading and the A/B compare phase. It's in the main swap group, so it loads on demand and swaps in only for the grading phase (after generation), never competing for VRAM with a model under test. Nothing extra to start.

## Updating

```bash
docker compose pull
docker compose build llm-swap
docker compose up -d
```

## Resource notes

- 2× R9700 = 64 GB VRAM. gpt-oss-120b (~65 GB MXFP4) tensor-split across both leaves only ~3 GB headroom — long contexts get tight, watch for OOM on multi-tool tool-call chains.
- Plex transcoding uses VAAPI on `/dev/dri` — separate from llama.cpp's ROCm compute on `/dev/kfd`. No contention.
- HuggingFace cache lives on `/mnt/cache/huggingface/` (SATA SSD, ~500 GB).
