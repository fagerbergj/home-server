# OpenCode Setup

Configures [OpenCode](https://opencode.ai) to use the local llm-swap instance as its LLM backend.

## Config file

Place at `~/.config/opencode/opencode.json` (global) or `opencode.json` in a project root (per-project):

> Model keys come from `llm-swap.yaml`. Context limits should match the `-c` flag in that model's `cmd`.

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "llm-swap": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "llm-swap (Local)",
      "options": {
        "baseURL": "http://jason-server:11436/v1",
        "apiKey": "unused"
      },
      "models": {
        "qwen3-coder-next": {
          "name": "Qwen3 Coder Next (256K)",
          "limit": {
            "context": 262144,
            "output": 8192
          }
        },
        "gpt-oss-120b": {
          "name": "gpt-oss-120b (32K)",
          "limit": {
            "context": 32768,
            "output": 8192
          }
        },
        "qwen3.6-35b": {
          "name": "Qwen3.6 35B (32K)",
          "limit": {
            "context": 32768,
            "output": 8192
          }
        }
      }
    }
  },
  "model": "llm-swap/qwen3-coder-next"
}
```

## Access

`jason-server` resolves via Tailscale MagicDNS once the client is enrolled (see [networking/setup.md](../networking/setup.md) Phase 7) — the same `baseURL` works on LAN and remotely. llm-swap doesn't enforce API keys; tailnet membership is the access boundary. The `"unused"` placeholder is just to satisfy OpenCode's required-field validation.

## Verify

1. Run `opencode` in any project
2. Run `/models` — you should see the three models listed above
3. Send a test message and confirm a response
4. Confirm the model loaded on GPU:
   ```bash
   ssh jason-server 'rocm-smi'
   ```
   Should show non-trivial VRAM usage on at least one GPU during the request.
