#!/usr/bin/env bash
# Run promptfoo evals against the llm-swap stack, one model at a time.
# Judge (llm-judge) must be running: make -C .. judge-up
#
# Usage:
#   ./eval.sh                    # all models
#   ./eval.sh qwen3.5-9b        # single model

set -euo pipefail

# --tools flag runs the tool-reasoning eval suite instead of general knowledge
CONFIG=promptfooconfig.llm-swap.yaml
if [[ "${1:-}" == "--tools" ]]; then
  CONFIG=promptfooconfig.tools.yaml
  shift
fi

# Model → max concurrent test cases.
# Bigger/slower models get lower concurrency to avoid timeout pile-ups.
declare -A CONCURRENCY=(
  ["llama-3.3-70b"]=1
  ["qwen3.6-35b"]=2
  ["qwen3.5-9b"]=4
  ["qwen3-vl-8b"]=2
  ["qwen3-coder-next"]=1
)

if [[ $# -gt 0 ]]; then
  MODELS=("$@")
else
  MODELS=("${!CONCURRENCY[@]}")
fi

for model in "${MODELS[@]}"; do
  concurrency="${CONCURRENCY[$model]:-2}"
  echo ""
  echo "════════════════════════════════════════"
  echo "  Model: $model  (concurrency: $concurrency)"
  echo "════════════════════════════════════════"
  export MODEL="$model"
  npx promptfoo@latest eval -c "$CONFIG" --max-concurrency "$concurrency" --output "evals/${model}.json"
done

echo ""
echo "All done. View results: npx promptfoo@latest view"
