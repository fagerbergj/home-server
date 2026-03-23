# OpenCode Setup

Configures [OpenCode](https://opencode.ai) to use the local Ollama instance as its LLM backend.

## Config file

Place at `~/.config/opencode/opencode.json` (global) or `opencode.json` in a project root (per-project):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Ollama (Local)",
      "options": {
        "baseURL": "http://192.168.50.186:11434/v1",
        "apiKey": "{env:OLLAMA_API_KEY}"
      },
      "models": {
        "gpt-oss-20b-64k": {
          "name": "GPT-OSS 20B (64K)",
          "limit": {
            "context": 65536,
            "output": 8192
          }
        },
        "omnicoder-9b-128k": {
          "name": "OmniCoder 9B (128K)",
          "limit": {
            "context": 131072,
            "output": 8192
          }
        },
        "qwen3-4b-32k": {
          "name": "Qwen3 4B (32K)",
          "limit": {
            "context": 32768,
            "output": 8192
          }
        }
      }
    }
  },
  "model": "ollama/gpt-oss-20b-64k"
}
```

## API key

The key is the same one used by NPM to protect the external endpoint. Get it from the server:

```bash
grep OLLAMA_API_KEY ~/workspace/home-server/.env
```

Then export it in your shell profile (`~/.bashrc` or `~/.zshrc`):

```bash
export OLLAMA_API_KEY=your-key-here
```

## External access (off home network)

Swap the `baseURL` for the external endpoint:

```json
"baseURL": "https://llm-api.jasonfagerberg.duckdns.org/v1"
```

Auth is the same API key — enforced by NPM, not Ollama.

## Verify

1. Run `opencode` in any project
2. Run `/models` — you should see GPT-OSS 20B (64K), OmniCoder 9B (128K), and Qwen3 4B (32K) listed
3. Send a test message and confirm a response
4. Check the model loaded on GPU:
   ```bash
   ssh jason-server 'docker exec ollama ollama ps'
   ```
   Should show `gpt-oss-20b-64k` with `100% GPU`
