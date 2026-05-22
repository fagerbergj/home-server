# Model evaluation (promptfoo)

Runs the llm-swap model lineup across ten test suites and an A/B compare phase.
All model-graded assertions (g-eval, factuality, closedqa, llm-rubric) use the
GPU judge (`selene` in llm-swap, port 11436). At concurrency 1 promptfoo defers
grading, so every model generation runs first and the judge swaps in once for the
batched grading phase — no model is resident when it judges, so the judge gets the
full GPU.

## Directory layout

```
promptfoo/
├── configs/         promptfooconfig.<suite>.yaml + promptfooconfig.compare.yaml
├── test-suites/     <suite>.yaml (one per suite)
│   ├── agentic/     provider.js, Dockerfile, entrypoint.sh (agentic sandbox)
│   ├── large-code/  hidden pytest specs the agentic suite grades against
│   └── scripts/     tools-grader.js
├── scripts/         eval.sh, compare.sh, summarize.sh, lint-tests.py
├── evals/           <model>-<suite>.json + README.md (results) + COMPARE.md
└── eval-config.yaml model → suite assignments + concurrency
```

Suite name == config stem == test-file stem (e.g. `coding` → `configs/promptfooconfig.coding.yaml` + `test-suites/coding.yaml`).

| Suite | Grading | A/B compare? |
|---|---|---|
| architecture | g-eval (0-1 criteria) | ✅ |
| coding | g-eval (0-1 criteria) | ✅ |
| calibration | model-graded-closedqa (binary) | ✅ |
| brain-twisters | factuality + g-eval + javascript | ✅ |
| chat | g-eval + javascript (prompt contract) | — |
| math | deterministic (final-answer match) | — |
| cruxeval | deterministic + llm-rubric (output match + gotchas) | — |
| hard-reasoning | deterministic (letter / grid match) | — |
| agentic | opencode self-directs in a sandbox container; hidden pytest grades (reports tokens/turns) | — |
| tools | deterministic JSON (tools-grader.js) | — |

Only the four model-graded suites get the A/B compare phase — for deterministic suites the per-model pass rate already is the comparison, and a "pick the best" judge would just add noise (it might prefer a confident-but-wrong answer).

## Quickstart

Requires Node.js 18+ (`node --version`). promptfoo runs via `npx`, no install needed.

The judge (`selene`) is a model in `llm-swap.yaml` and loads on demand during the grading phase — nothing extra to start.

The `agentic` suite runs on **jason-server** (needs Docker + the local llm-swap). Build the sandbox image once — it bundles pytest + the task deps (aiohttp, pygame), so no host Python env is needed:

```bash
docker build -t oc-agent test-suites/agentic
```

Agent runs are nondeterministic, so run the suite with caching off:

```bash
PROMPTFOO_CACHE_ENABLED=false ./scripts/eval.sh --suite agentic
```

## Running

Scripts cd to the promptfoo root themselves, so they work from anywhere:

```bash
cd llm/promptfoo

# Per-model evals: all models × their suites
./scripts/eval.sh

# One model, all its suites
./scripts/eval.sh qwen3.6-35b

# Several models (re-run just the ones that changed)
./scripts/eval.sh gpt-oss-120b qwen3.6-35b qwen3-coder-next

# One suite, all models
./scripts/eval.sh --suite coding

# One suite, one model (fast inner loop)
./scripts/eval.sh --suite math qwen3.6-35b

# Tool-call routing only (opt-in)
./scripts/eval.sh --tools [model ...]

# Blind A/B comparison — separate step, runs off the cached per-model
# outputs against the GPU judge. All four rubric suites or just one:
./scripts/compare.sh
./scripts/compare.sh architecture
```

Results land in `evals/<model>-<suite>.json`. `summarize.sh` (run automatically after each eval) aggregates them into `evals/README.md` (per-model table + failure details) and `evals/COMPARE.md` (pairwise win matrix). Force a fresh run, bypassing cache:

```bash
PROMPTFOO_CACHE_ENABLED=false ./scripts/eval.sh ...
```

(Don't use `--no-cache` with `compare.sh` — it relies on cached model outputs so only the judge runs.)

## Viewing results

```bash
npx promptfoo@latest view
```

Opens the web UI: pass/fail per test, rubric reasons, side-by-side completions across models.

## Test conventions

- Each `test-suites/<suite>.yaml` is a list of `{description, vars: {task: ...}, assert: [...]}` entries.
- Model-graded assertions use the type that fits the suite: `g-eval` (criteria list, 0-1, `threshold: 0.7`) for open-ended quality, `factuality` (vs a reference answer, `differButFactual: 0` so only true agreement passes) for one-right-answer questions, `model-graded-closedqa` (binary Y/N) for pass/fail behavior, and `llm-rubric` (1-5, `threshold: 4`) where a tiered rubric still fits.
- Deterministic assertions (`type: javascript`) return `{pass, score, reason}`. Score 5 = pass, 0 = fail; intermediate scores (e.g. 2 for "right routing but PROD-BROKEN format" in tools) describe the failure mode.
- `file://` grader paths are written `file://../test-suites/scripts/<grader>.js`. promptfoo resolves them relative to the config dir (`configs/`), so the `../test-suites/` hop is needed to reach the grader scripts.
- After editing a test file, run `python3 scripts/lint-tests.py` to canonicalise the YAML (round-trip safety check included).

## Adding a model

1. Add it to `llm/llm-swap.yaml`.
2. Add it under `models:` in `eval-config.yaml` with the suite list.
3. Run `./scripts/eval.sh <model>` — per-suite configs use `{{ env.MODEL }}` so they pick up the new key automatically. Add it to `configs/promptfooconfig.compare.yaml` too if you want it in the A/B matrix.

## Adding a suite

1. Write `test-suites/<name>.yaml` (mirror an existing one).
2. Copy a `configs/promptfooconfig.<x>.yaml` to `configs/promptfooconfig.<name>.yaml`; set `tests: ../test-suites/<name>.yaml` and set `threshold` to match the assertion type (0.7 for g-eval; none for closedqa/factuality).
3. Add `<name>` to `SUITES` in `scripts/eval.sh` (and to `COMPARE_SUITES` there + in `scripts/compare.sh` if it's model-graded).
4. Add `<name>` to each relevant model's `suites:` list in `eval-config.yaml`.

## Notes on the judge

The judge is Atla Selene-1 70B (`mradermacher/Selene-1-Llama-3.3-70B-i1-GGUF:Q4_K_M`), purpose-trained for 1-5 rubric scoring. It's the `selene` model in llm-swap (port 11436), used for both per-model rubric grading and the compare phase.

Both run at concurrency 1 so promptfoo batches all judge calls after generation: the model under test generates everything, then swaps out and Selene swaps in once to grade — so the 70B judge gets the full GPU and never competes with a model under test.

Rubrics are phrased semantically (`"any concrete command, tool, or query counts"`) rather than naming specific keywords. See `test-suites/calibration.yaml` for the canonical examples.
