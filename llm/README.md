# Local LLM (`llm-swap-media` + `jaison/llm`)

OpenAI-compatible LLM gateway backed by [llama-swap](https://github.com/mostlygeek/llama-swap). On `jason-server` (media box, RTX 3090 24 GB), `llm-swap-media` serves the local CUDA models (`clef`, `clef-flash`, `qwen3-omni-30b`) and peers to `jaison` (`192.168.50.202:11436`, 4× AMD Radeon AI Pro R9700 128 GB VRAM total) for all big models and CPU embeddings. Both `quack` and Traefik's public `/openai` route (`api/traefik/dynamic/llm.yml`) talk to `llm-swap-media`.

## Access

- LAN: `http://192.168.50.186:11436/v1`
- Tailnet: `http://jason-server:11436/v1`
- Public (API key via Traefik): `https://api.jasonfagerberg.duckdns.org/openai/v1`

## Model lineup

### Media box (`llm/llm-swap-media.yaml`, RTX 3090 CUDA)

| Key | Role | Notes |
|---|---|---|
| `clef` | Resident decision model (`ttl: 0`, preloaded) | Clef 27B Q4_K_M + mmproj, `-c 8192 -b 8192 -ub 8192 -np 1 -ngl 999` |
| `clef-flash` | On-demand 9B decision model (`ttl: 3600`) | Clef-Flash Q4_K_M, `-c 32768 -b 16384 -ub 16384 -np 1 -ngl 999` |
| `qwen3-omni-30b` | On-demand media reader (`ttl: 1800`) | Image + audio; swaps with `clef` in the `3090` group |

### Peered to `jaison` (`jaison/llm/llm-swap.yaml`, 4× R9700 + 128 GB RAM)

| Key | Runtime | Notes |
|---|---|---|
| `qwen3-embed` | llama.cpp CPU (`ttl: 0`, persistent, preloaded) | Qwen3-Embedding-4B Q8_0, `-t 24 -c 16384 --parallel 4 -ub 4096 -b 4096` |
| `qwen3.8-flash-next` | Strata v0.2.19 (`ttl: 0`, resident default, preloaded) | UD-Q4_K_XL split-4 + DFlash2 + GPU vision, 416k INT8 KV (262k ctx, 8 lanes) |
| `qwen3.8-27b` | vLLM ROCm TP=4 (`ttl: 3600`, on-demand) | Offline-merged super-adapter FP8 + DFlash2 int4 draft, 262k ctx, 1.18M bf16 KV |
| `hy4-flash` | llama.cpp ROCm (`ttl: 3600`, on-demand) | AngelSlim Q4_K_M, Engram table paged from NVMe, 524k `q8_0` KV, text-only (`NO_MM=1`) |

See [`jaison/llm/README.md`](../jaison/llm/README.md) for `jaison`'s runtime details and cold-storage launchers.

## Pre-pulling models

```bash
./download-models.sh   # pulls active GGUFs into /mnt/media/models/huggingface (override via HF_CACHE)
```

## API

```bash
# Chat
curl http://192.168.50.186:11436/v1/chat/completions \
  -H 'content-type: application/json' \
  -d '{"model": "qwen3.8-flash-next", "messages": [{"role": "user", "content": "Hello!"}]}'

# Embeddings
curl http://192.168.50.186:11436/v1/embeddings \
  -H 'content-type: application/json' \
  -d '{"model": "qwen3-embed", "input": "some text"}'

# List declared models
curl http://192.168.50.186:11436/v1/models
```

## Updating (media box)

```bash
make media-up
```
