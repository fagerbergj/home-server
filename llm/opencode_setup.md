# OpenCode Setup

Configures [OpenCode](https://opencode.ai) to use the local Ollama instance as its LLM backend.

## Config file

Place at `~/.config/opencode/opencode.json` (global) or `opencode.json` in a project root (per-project):

> Context length can be found by doing `docker exec ollama ollama show <model>`

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
        "qwen35-coding": {
          "name": "Qwen3.5 35B Coding (128K)",
          "limit": {
            "context": 131072,
            "output": 8192
          }
        },
        "qwen35-chat": {
          "name": "Qwen3.5 35B Chat (8K)",
          "limit": {
            "context": 8192,
            "output": 8192
          }
        }
      }
    }
  },
  "model": "ollama/qwen35-coding"
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
2. Run `/models` — you should see Qwen3.5 35B Coding (128K) and Qwen3.5 35B Chat (8K) listed
3. Send a test message and confirm a response
4. Check the model loaded on GPU:
   ```bash
   ssh jason-server 'docker exec ollama ollama ps'
   ```
   Should show `qwen35-coding` with `100% GPU`
