# OpenCode Setup

Configure OpenCode to use the local Ollama API.

## Config

Run this to write the config file:

```bash
mkdir -p ~/.config/opencode && cat > ~/.config/opencode/opencode.json << 'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "model": "ollama/qwen2.5-coder:7b",
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Ollama",
      "options": {
        "baseURL": "https://llm-api.jasonfagerberg.duckdns.org/v1",
        "apiKey": "{env:OLLAMA_API_KEY}"
      },
      "models": {
        "qwen2.5-coder:7b": {
          "name": "qwen2.5-coder:7b"
        }
      }
    }
  }
}
EOF
```

Or manually edit `~/.config/opencode/opencode.json`.

## API Key

Add to your shell profile (`~/.bashrc` or `~/.zshrc`):

```bash
export OLLAMA_API_KEY=<your-key from NPM nginx config>
```

## Select the Model

In OpenCode, run `/models` and select `ollama > qwen2.5-coder:7b`.
