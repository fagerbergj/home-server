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

# Salvage: the model sometimes writes its output to an absolute path (e.g.
# /solution.py, /ARCHITECTURE.md) instead of into /work. Copy it into /work so
# grading/capture can find it. (Seeded bugfix edits the repo already in /work.)
salvage() {  # $1 = relpath under /work
  local rel="$1" base f
  [ -f "/work/$rel" ] && return 0
  base=$(basename "$rel")
  f=$(find / -maxdepth 3 -name "$base" 2>/dev/null | grep -v '^/work/' | head -1)
  [ -n "$f" ] && mkdir -p "/work/$(dirname "$rel")" && cp "$f" "/work/$rel"
  return 0
}
case "${MODE:-solo}" in
  solo) salvage solution.py ;;
  summarize|review) case "${CAPTURE:-}" in file:*) salvage "${CAPTURE#file:}" ;; esac ;;
esac
true
