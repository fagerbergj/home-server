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
# NOTE: relies on promptfoo cache for the model generations — it re-judges
# existing responses. The --no-cache flag is available but forces a full
# regenerate-and-judge (every model reloads per test = thrash); use sparingly.

set -euo pipefail
cd "$(dirname "$0")/.."   # promptfoo root

# --no-cache: opt out of the cached generations (forces fresh, slow). Strip it
# before the positional suite arg is read.
args=()
for a in "$@"; do
  if [ "$a" = "--no-cache" ]; then export PROMPTFOO_CACHE_ENABLED=false
  else args+=("$a"); fi
done
if [ "${#args[@]}" -gt 0 ]; then set -- "${args[@]}"; else set --; fi

ALL_COMPARE_SUITES=(architecture coding calibration brain-twisters)
COMPARE_SUITES=("${ALL_COMPARE_SUITES[@]}")

if [[ $# -gt 0 ]]; then
  case " ${ALL_COMPARE_SUITES[*]} " in
    *" $1 "*) COMPARE_SUITES=("$1") ;;
    *) echo "error: '$1' is not a compare suite. Choose: ${ALL_COMPARE_SUITES[*]}" >&2; exit 1 ;;
  esac
fi

# Drop stale compare outputs for suites no longer in the compare set — a de-listed
# suite or a removed model lingering in old JSON would otherwise still show up in
# COMPARE.md (e.g. a de-listed suite, or a model no longer in the lineup).
for f in evals/compare-*.json; do
  [ -e "$f" ] || continue
  s=$(basename "$f" .json); s=${s#compare-}
  case " ${ALL_COMPARE_SUITES[*]} " in
    *" $s "*) ;;
    *) echo "removing stale $f"; rm -f "$f" ;;
  esac
done

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
      --max-concurrency 1 \
      --output "evals/compare-${suite}.json" || true
done

bash scripts/summarize.sh --compare
