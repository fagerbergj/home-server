# Model evaluation (promptfoo)

Runs the llm-swap model lineup across ten test suites and an A/B compare phase.
Per-model rubric suites use the CPU judge (`llm-judge` profile, port 11437) so
it coexists with the model under test; the compare phase uses the GPU judge
(`selene` in llm-swap) since it runs off cached outputs with no model resident.

## Directory layout

```
promptfoo/
├── configs/         promptfooconfig.<suite>.yaml + promptfooconfig.compare.yaml
├── test-suites/     <suite>.yaml (one per suite)
│   ├── large-code/  per-test pytest fixtures (trie/, markdown/, …)
│   └── scripts/     tools-grader.js, large-code-grader.js, large-code-runner.sh
├── scripts/         eval.sh, compare.sh, summarize.sh, lint-tests.py
├── evals/           <model>-<suite>.json + README.md (results) + COMPARE.md
└── eval-config.yaml model → suite assignments + concurrency
```

Suite name == config stem == test-file stem (e.g. `coding` → `configs/promptfooconfig.coding.yaml` + `test-suites/coding.yaml`).

| Suite | Grading | A/B compare? |
|---|---|---|
| architecture | rubric | ✅ |
| coding | rubric | ✅ |
| calibration | rubric | ✅ |
| brain-twisters | rubric | ✅ |
| function-call | rubric + javascript | — |
| math | deterministic (final-answer match) | — |
| cruxeval | deterministic (output match) | — |
| hard-reasoning | deterministic (letter / grid match) | — |
| large-code | compile + pytest (large-code-grader.js → large-code-runner.sh) | — |
| tools | deterministic JSON (tools-grader.js) | — |

Only rubric-graded suites get the A/B compare phase — for deterministic suites the per-model pass rate already is the comparison, and a "pick the best" judge would just add noise (it might prefer a confident-but-wrong answer).

## Quickstart

Requires Node.js 18+ (`node --version`). promptfoo runs via `npx`, no install needed.

Per-model rubric suites need the CPU judge up:

```bash
docker compose --profile judge up -d llm-judge
```

The compare phase instead uses the GPU judge (`selene`), which is already a model in `llm-swap.yaml` — nothing extra to start.

For the `large-code` suite, set up a Python venv with pytest + the deps the test files import:

```bash
uv venv ~/.venvs/eval
~/.venvs/eval/bin/uv pip install pytest aiohttp pygame
```

(Plain `python3 -m venv` + `pip install` works too.)

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
- Rubric assertions use Selene's native 1-5 format with `threshold: 4` — Score 4 or 5 passes.
- Deterministic assertions (`type: javascript`) return `{pass, score, reason}`. Score 5 = pass, 0 = fail; intermediate scores (e.g. 2 for "right routing but PROD-BROKEN format" in tools) describe the failure mode.
- `file://` grader paths in test files are relative to the test file, so they point at `scripts/<grader>.js` (i.e. `test-suites/scripts/`).
- After editing a test file, run `python3 scripts/lint-tests.py` to canonicalise the YAML (round-trip safety check included).

## Adding a model

1. Add it to `llm/llm-swap.yaml`.
2. Add it under `models:` in `eval-config.yaml` with the suite list.
3. Run `./scripts/eval.sh <model>` — per-suite configs use `{{ env.MODEL }}` so they pick up the new key automatically. Add it to `configs/promptfooconfig.compare.yaml` too if you want it in the A/B matrix.

## Adding a suite

1. Write `test-suites/<name>.yaml` (mirror an existing one).
2. Copy a `configs/promptfooconfig.<x>.yaml` to `configs/promptfooconfig.<name>.yaml`; set `tests: ../test-suites/<name>.yaml` and adjust the rubric.
3. Add `<name>` to `SUITES` in `scripts/eval.sh` (and to `COMPARE_SUITES` there + in `scripts/compare.sh` if it's rubric-graded).
4. Add `<name>` to each relevant model's `suites:` list in `eval-config.yaml`.

## Notes on the judges

Both judges run Selene-1-Mini-Llama-3.1-8B (`bartowski/Selene-1-Mini-Llama-3.1-8B-GGUF:Q4_K_M`), trained for 1-5 rubric scoring:

- **CPU judge** (`llm-judge` container, port 11437) — per-model rubric suites. CPU keeps VRAM free for the model under test (gpt-oss-120b leaves zero headroom for a co-resident judge).
- **GPU judge** (`selene` model in llm-swap, port 11436) — the compare phase only. Compare runs off cached model outputs, so no model is resident and Selene gets the full GPU.

Selene pattern-matches keyword overlap in rubric criteria, so rubrics are phrased semantically (`"any concrete command, tool, or query counts"`) rather than naming specific keywords. See `test-suites/calibration.yaml` for the canonical examples.
