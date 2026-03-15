# OpenCode Setup

Configure OpenCode to use the local Ollama API.

## Config

Add to `~/.config/opencode/opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Ollama",
      "options": {
        "baseURL": "https://llm-api.jasonfagerberg.asuscomm.com/v1",
        "apiKey": "{env:OLLAMA_API_KEY}"
      },
      "models": {
        "qwen3:8b": {
          "name": "qwen3:8b"
        }
      }
    }
  }
}
```

## API Key

Add to your shell profile (`~/.bashrc` or `~/.zshrc`):

```bash
export OLLAMA_API_KEY=<your-key from llm/.env>
```

## Select the Model

In OpenCode, run `/models` and select `ollama > qwen3:8b`.
