#!/usr/bin/env bash
# Re-run the blind A/B compare phase only, judged by the GPU Selene on llm-swap.
#
# The per-model suites must already have run (their outputs are reused from
# promptfoo's cache), so this just re-judges existing responses — fast, and
# the GPU has no model-under-test resident so Selene runs at full speed.
#
# Usage:
#   ./compare.sh                 # all compare suites
#   ./compare.sh architecture    # one suite
#
# Compare suites (subjective, rubric-gradable): architecture, calibration,
# hard-reasoning, brain-twisters. Deterministic suites are excluded — A/B adds
# no signal when an answer is simply right or wrong.
#
# NOTE: relies on promptfoo cache for the model generations. Do NOT set
# PROMPTFOO_CACHE_ENABLED=false or every model will reload per test (thrash).

set -euo pipefail

COMPARE_SUITES=(architecture calibration hard-reasoning brain-twisters)

declare -A TESTS=(
  [architecture]=architecture-tests.yaml
  [calibration]=calibration-tests.yaml
  [hard-reasoning]=hard-reasoning-tests.yaml
  [brain-twisters]=brain-twister-tests.yaml
)

if [[ $# -gt 0 ]]; then
  if [[ -z "${TESTS[$1]:-}" ]]; then
    echo "error: '$1' is not a compare suite. Choose: ${COMPARE_SUITES[*]}" >&2
    exit 1
  fi
  COMPARE_SUITES=("$1")
fi

for suite in "${COMPARE_SUITES[@]}"; do
  echo "──────────────────────────────────────────────────"
  echo "  A/B compare: $suite"
  echo "──────────────────────────────────────────────────"
  COMPARE_TESTS_FILE="${TESTS[$suite]}" \
    npx promptfoo@latest eval \
      -c promptfooconfig.compare.yaml \
      --max-concurrency 2 \
      --output "evals/compare-${suite}.json"
done

bash summarize.sh
echo "Wrote COMPARE.md"
