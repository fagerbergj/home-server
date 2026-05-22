#!/usr/bin/env bash
# Writes an opencode config for the llm-swap provider, then runs opencode
# headless on $TASK with $MODEL. Emits the --format json event stream on stdout;
# files the model writes land in /work (mount a sandbox there).
#   LLM_SWAP_URL  e.g. http://localhost:11436/v1 (on jason-server) or
#                 http://jason-server:11436/v1 (over tailscale)
#   MODEL         e.g. qwen3.5-9b
#   TASK          the prompt (pinned public API; do NOT mention the hidden tests)
set -euo pipefail
: "${LLM_SWAP_URL:?need LLM_SWAP_URL}"
: "${MODEL:?need MODEL}"
: "${TASK:?need TASK}"

mkdir -p /root/.config/opencode
cat > /root/.config/opencode/opencode.json <<JSON
{
  "\$schema": "https://opencode.ai/config.json",
  "provider": {
    "llm-swap": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "llm-swap",
      "options": { "baseURL": "${LLM_SWAP_URL}", "apiKey": "llm-swap" },
      "models": { "${MODEL}": { "name": "${MODEL}" } }
    }
  },
  "permission": { "edit": "allow", "bash": "allow" }
}
JSON

exec opencode run "${TASK}" \
  -m "llm-swap/${MODEL}" \
  --pure --format json --dangerously-skip-permissions \
  --dir /work
