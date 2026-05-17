#!/usr/bin/env bash
# Run promptfoo evals against the llm-swap stack, one model at a time.
# Judge (llm-judge) must be running: make -C .. judge-up
#
# Usage:
#   ./eval.sh                         # general knowledge, all models
#   ./eval.sh qwen3.5-9b             # general knowledge, single model
#   ./eval.sh --math [model]          # GSM8K math word problems
#   ./eval.sh --coding [model]        # HumanEval Python coding
#   ./eval.sh --function-call [model] # BFCL function calling
#   ./eval.sh --tools [model]         # document-pipeline tool routing

set -euo pipefail

# Select test suite from first arg
CONFIG=promptfooconfig.llm-swap.yaml
case "${1:-}" in
  --math)          CONFIG=promptfooconfig.math.yaml;          shift ;;
  --coding)        CONFIG=promptfooconfig.coding.yaml;        shift ;;
  --function-call) CONFIG=promptfooconfig.function-call.yaml; shift ;;
  --tools)         CONFIG=promptfooconfig.tools.yaml;         shift ;;
esac

# Model → max concurrent test cases.
# Bigger/slower models get lower concurrency to avoid timeout pile-ups.
declare -A CONCURRENCY=(
  ["llama-3.3-70b"]=1
  ["qwen3.6-35b"]=2
  ["qwen3.5-9b"]=4
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
  echo "  Suite: $CONFIG"
  echo "  Model: $model  (concurrency: $concurrency)"
  echo "════════════════════════════════════════"
  export MODEL="$model"
  npx promptfoo@latest eval -c "$CONFIG" --max-concurrency "$concurrency" \
    --output "evals/${model}-$(basename $CONFIG .yaml).json"
done

echo ""
echo "All done. View results: npx promptfoo@latest view"
