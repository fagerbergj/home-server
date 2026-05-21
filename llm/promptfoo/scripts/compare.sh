#!/usr/bin/env bash
# Re-run the blind A/B compare phase only, judged by the GPU Selene on llm-swap.
#
# The per-model suites must already have run (their outputs are reused from
# promptfoo's cache), so this just re-judges existing responses — fast, and
# the GPU has no model-under-test resident so Selene runs at full speed.
#
# Usage (run from anywhere — the script cd's to the promptfoo root):
#   ./scripts/compare.sh                 # all compare suites
#   ./scripts/compare.sh architecture    # one suite
#
# Compare suites (rubric-graded): architecture, coding, calibration,
# brain-twisters. Deterministic suites are excluded — A/B adds no signal when
# an answer is simply right or wrong.
#
# NOTE: relies on promptfoo cache for the model generations. Do NOT set
# PROMPTFOO_CACHE_ENABLED=false or every model will reload per test (thrash).

set -euo pipefail
cd "$(dirname "$0")/.."   # promptfoo root

COMPARE_SUITES=(architecture coding calibration brain-twisters)

if [[ $# -gt 0 ]]; then
  case " ${COMPARE_SUITES[*]} " in
    *" $1 "*) COMPARE_SUITES=("$1") ;;
    *) echo "error: '$1' is not a compare suite. Choose: ${COMPARE_SUITES[*]}" >&2; exit 1 ;;
  esac
fi

for suite in "${COMPARE_SUITES[@]}"; do
  echo "──────────────────────────────────────────────────"
  echo "  A/B compare: $suite"
  echo "──────────────────────────────────────────────────"
  # promptfoo exits non-zero when any test "fails" — in a select-best compare
  # only the winner passes, so that's every run. Tolerate it so the loop
  # continues through all suites.
  COMPARE_TESTS_FILE="../test-suites/${suite}.yaml" \
    npx promptfoo@latest eval \
      -c configs/promptfooconfig.compare.yaml \
      --max-concurrency 4 \
      --output "evals/compare-${suite}.json" || true
done

bash scripts/summarize.sh
echo "Wrote evals/COMPARE.md"
