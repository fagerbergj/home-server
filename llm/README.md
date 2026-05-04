# Local LLM (Ollama)

Runs [Ollama](https://ollama.com) in Docker with GPU-accelerated inference on an RTX 3090 (24GB VRAM). [Open WebUI](https://github.com/open-webui/open-webui) provides a chat interface.

## Access

Open WebUI:
- LAN: `http://192.168.50.186:3000`
- Public: `https://llm.jasonfagerberg.duckdns.org`

Ollama API (tailnet-only — see [networking/setup.md](../networking/setup.md) Phase 7):
- LAN: `http://192.168.50.186:11434`
- Tailnet: `http://jason-server:11434`

## Evaluating a model

Before pulling a model, use `check-compaitbility.sh` to estimate VRAM. All parameters come from the model's blob page on ollama.com (navigate to the model → **Files** tab → click the blob hash).

### Reading the blob page

| Script flag | Ollama blob field | Notes |
|-------------|-------------------|-------|
| `-f` | Model size | Convert to GiB — close enough |
| `-q` | `general.file_type` (e.g. `Q4_K_M`) | Extract the number: `4` |
| `-e` | `*.embedding_length` | |
| `-b` | `*.block_count` | |
| `-k` | `*.attention.head_count_kv` | Different from `*.attention.head_count` — always provide if shown |
| `-d` | `*.attention.key_length` | Same value as `*.attention.value_length` |
| `-c` | Your intended context size | See guidance below — NOT the model's `*.context_length` max |
| `-t` | KV cache type | Match `OLLAMA_KV_CACHE_TYPE` env var (default `f16`, set to `q8_0` in this stack) |
| `-a` | Architecture type: `transformer`, `ssm` | Use `ssm` when `*.attention.head_count_kv` is an array — see below |

```bash
./check-compaitbility.sh -f 15 -q 4 -e 5120 -b 40 -k 8 -d 128 -c 32768 -t q8_0
```

**RAM spillage is fine.** Ollama automatically spills the KV cache to CPU RAM when VRAM is exhausted. With 32GB system RAM there's plenty of headroom — you'll just see slower inference on very long contexts.

### GQA models

Models where `*.attention.head_count_kv` is lower than `*.attention.head_count` use Grouped Query Attention — their KV cache is much smaller. Always pass `-k` for these or the estimate will be significantly too high. Example: a model with 32 attention heads but 8 KV heads (`-k 8`) has a 4x smaller KV cache.

### MoE models

Models with `*.expert_count` and `*.expert_used_count` fields only activate a fraction of their weights per token. The file size already reflects this (a 30B MoE model with 3B active params has a proportionally smaller file), so `-f` is still correct. The KV cache estimate is also unaffected — it depends on attention heads, not experts. MoE models can handle large context more cheaply than their total parameter count suggests.

### Hybrid SSM/attention models (Mamba, nemotron-cascade, etc.)

These interleave attention layers with state space model (SSM) layers — look for `*.ssm.state_size` or `*.ssm.conv_kernel` fields on the blob page. `*.attention.head_count_kv` will appear as an array of mixed values or zeros rather than a single number.

Pass `-a ssm` and the script will skip the KV cache calculation entirely:

```bash
./check-compaitbility.sh -f 24 -q 4 -e 2688 -b 52 -a ssm
```

The KV cache line will show `N/A` and the total will be just weights + overhead. These models handle very long contexts cheaply — that's the point of the architecture.

---

## Model slots

### Coding model

One model, stays loaded. Prioritize **context size** over speed — coding tasks need enough context to hold multiple files or a long back-and-forth. Slow inference is fine. RAM spillage is fine.

**Target:** weights fit within ~20GB VRAM, leaving room for a large KV cache. Use `-c 32768` or higher and check the total.

Good candidates: models tagged `code` or `coding` on Ollama. GQA models (low `-k`) handle long context much more efficiently.

> **Note on hybrid SSM/attention models** (e.g. Qwen3.5): the script underestimates KV cache because it assumes all blocks use attention. Binary search with `ollama ps` to find the actual 100% GPU context limit. Example: qwen35-coder:latest (27.8B Q4_K_M) hits 100% GPU at **32768** context on a 3090.

### Chat model

Can be a large, high-quality model — context only needs to cover a conversation (4k–8k is usually enough). Prioritise model quality over context size.

**Target:** total VRAM under ~22GB at 8k context.

> **Example:** gemma4-26b (25.8B Q4_K_M) uses 21GB at 131072 context — 100% GPU.

```bash
./check-compaitbility.sh -f <size> -q 4 -e <embedding> -b <blocks> -k <kv_heads> -d <kv_len> -c 8192 -t q8_0
```

With 24GB VRAM and a small context window, 30B+ Q4 models fit comfortably.

### Specialized models

#### Computer vision

Look for models tagged `vision` on Ollama. The blob page will show additional vision fields (Vision Block Count, Vision Embedding Length, etc.). The vision encoder adds VRAM on top of what the script estimates — typically 1–3GB. Use a modest context (4k) since vision tasks don't need long context.

```bash
./check-compaitbility.sh -f <size> -q 4 -e <embedding> -b <blocks> -k <kv_heads> -d <kv_len> -c 4096 -t q8_0
```

---

## Chat via CLI

```bash
docker exec -it ollama ollama run <model>
```

## API

Ollama exposes an OpenAI-compatible REST API on port 11434:

```bash
curl http://192.168.50.186:11434/api/generate \
  -d '{"model": "<model>", "prompt": "Hello!", "stream": false}'
```

From outside your home network — connect via Tailscale, then use any tool that supports a custom OpenAI-compatible base URL:
```
Base URL: http://jason-server:11434
API Key:  unused — tailnet membership is the access boundary
```

## Managing Models

```bash
docker exec -it ollama ollama list
docker exec -it ollama ollama pull <model>
docker exec -it ollama ollama rm <model>
docker exec -it ollama ollama stop <model>   # unload from VRAM without deleting
```

### Setting context length

Ollama defaults to 2048 tokens. To run a model at a specific context size:

```bash
docker exec -it ollama bash -c 'printf "FROM <model>\nPARAMETER num_ctx 32768" | ollama create <model-name>'
```

Use the context size you evaluated with `check-compaitbility.sh` — loading a larger context than VRAM can hold will cause spillage to RAM.

## Resource Notes

- RTX 3090 24GB VRAM — expect ~20–50 tokens/sec on Q4 models depending on size
- Plex NVENC transcoding and LLM inference share the GPU but rarely overlap in practice
- Model files are stored in `./data`
- KV cache quantized to `q8_0` via `OLLAMA_KV_CACHE_TYPE` — halves KV cache VRAM vs default FP16
- Flash attention enabled via `OLLAMA_FLASH_ATTENTION=1`

## Updating

```bash
docker compose pull
docker compose up -d
```
