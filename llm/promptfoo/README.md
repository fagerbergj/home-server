# Model evaluation (promptfoo)

Runs the llm-swap model lineup across ten test suites and an A/B compare phase. Judge is Selene-1-Mini (CPU-only via the `llm-judge` profile) — small enough to coexist with the model under test, rubric-grading-trained.

## Layout

| Suite | Tests | Promptfoo config | Grading |
|---|---|---|---|
| architecture | architecture-tests.yaml | promptfooconfig.architecture.yaml | rubric |
| coding | coding-tests.yaml | promptfooconfig.coding.yaml | rubric |
| math | math-tests.yaml | promptfooconfig.math.yaml | deterministic (final-answer match) |
| function-call | function-call-tests.yaml | promptfooconfig.function-call.yaml | rubric + javascript |
| brain-twisters | brain-twister-tests.yaml | promptfooconfig.brain-twisters.yaml | rubric |
| cruxeval | cruxeval-tests.yaml | promptfooconfig.cruxeval.yaml | deterministic |
| calibration | calibration-tests.yaml | promptfooconfig.calibration.yaml | rubric |
| hard-reasoning | hard-reasoning-tests.yaml | promptfooconfig.hard-reasoning.yaml | deterministic |
| large-code | large-code-tests.yaml | promptfooconfig.large-code.yaml | compile + pytest (large-code-grader.js → large-code-runner.sh) |
| tools | tool-tests.yaml | promptfooconfig.tools.yaml | deterministic JSON (tools-grader.js) |

Model → suite assignments live in `eval-config.yaml`. `eval.sh` orchestrates everything.

## Quickstart

Requires Node.js 18+ (`node --version`). promptfoo runs via `npx`, no install needed. The `llm-judge` container must be up:

```bash
docker compose --profile judge up -d llm-judge
```

For the `large-code` suite, set up a Python venv with pytest + a couple deps the test files import:

```bash
uv venv ~/.venvs/eval
~/.venvs/eval/bin/uv pip install pytest aiohttp pygame
```

(Plain `python3 -m venv` + `pip install` works too.)

## Running

```bash
cd llm/promptfoo

# Everything: all 4 models × their suites, then A/B compare phase
./eval.sh

# One model, all its suites
./eval.sh llama-3.3-70b

# One suite, all models
./eval.sh --suite coding

# One suite, one model (fast inner loop)
./eval.sh --suite math qwen3.6-35b

# Skip the cross-model compare phase
./eval.sh --no-compare

# Tool-call routing only (opt-in via --tools)
./eval.sh --tools [model]
```

Results land in `evals/<model>-<suite>.json`. `summarize.sh` aggregates them into `RESULTS.md` (per-model table + failure details) and `COMPARE.md` (pairwise win matrix from the compare phase). Force a fresh run (bypass cache):

```bash
PROMPTFOO_CACHE_ENABLED=false ./eval.sh ...
```

## Viewing results

```bash
npx promptfoo@latest view
```

Opens the web UI showing pass/fail per test, rubric reasons, and side-by-side completions across models.

## Test conventions

- Each `*-tests.yaml` is a list of `{description, vars: {task: ...}, assert: [...]}` entries.
- Rubric assertions use Selene's native 1-5 rubric format with `threshold: 4` — Score 4 or 5 passes.
- Deterministic assertions (`type: javascript`) return `{pass, score, reason}`. By convention, score 5 = pass, 0 = fail; intermediate scores (e.g. 2 for "right routing but PROD-BROKEN format" in tool-tests) describe the failure mode.
- After editing a test file, run `python3 lint-tests.py` to canonicalise the YAML (round-trip safety check included).

## Adding a model

1. Add it to `llm/llm-swap.yaml`.
2. Add it under `models:` in `eval-config.yaml` with the suite list.
3. Run `./eval.sh <model>` — the per-suite configs use `{{ env.MODEL }}` interpolation so they pick up the new key automatically.

## Adding a suite

1. Write `<name>-tests.yaml` (mirror the shape of any existing one).
2. Copy an existing `promptfooconfig.*.yaml` as `promptfooconfig.<name>.yaml`; adjust `tests:` and any rubric.
3. Register the pair in `SUITE_CONFIG` at the top of `eval.sh`.
4. Add `<name>` to each relevant model's `suites:` list in `eval-config.yaml`.

## Notes on the judge

Selene-1-Mini-Llama-3.1-8B (`bartowski/Selene-1-Mini-Llama-3.1-8B-GGUF:Q4_K_M`) runs CPU-only on port 11437 via the `llm-judge` profile. CPU is intentional — keeps VRAM free for the model under test and the eval is batch-mode anyway. Selene pattern-matches keyword overlap in rubric criteria, so rubrics are phrased semantically (`"any concrete command, tool, or query counts"`) rather than naming specific keywords. See `calibration-tests.yaml` for the canonical examples.
