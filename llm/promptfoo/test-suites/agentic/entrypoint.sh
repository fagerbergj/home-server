#!/usr/bin/env bash
# Writes an opencode config for the llm-swap provider, then runs opencode
# headless on $TASK with $MODEL. Emits the --format json event stream on stdout;
# files the model writes land in /work (mount a sandbox there).
#   LLM_SWAP_URL  e.g. http://localhost:11436/v1 (on jason-server) or
#                 http://jason-server:11436/v1 (over tailscale)
#   MODEL         e.g. qwen3.5-9b
#   TASK          the prompt (pinned public API; do NOT mention the hidden tests)
#   MODE          solo|seeded|review|summarize (default solo) — only solo salvages solution.py
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

opencode run "${TASK}" \
  -m "llm-swap/${MODEL}" \
  --pure --format json --dangerously-skip-permissions \
  --dir /work

# Salvage (solo only): the model sometimes writes solution.py with an absolute
# path (e.g. /solution.py) instead of into /work. Copy it into /work so grading
# finds it. Seeded/review/summarize modes edit the repo already in /work.
if [ "${MODE:-solo}" = "solo" ] && [ ! -f /work/solution.py ]; then
  f=$(find / -maxdepth 3 -name solution.py 2>/dev/null | grep -v '^/work/' | head -1)
  [ -n "$f" ] && cp "$f" /work/solution.py
fi
true
