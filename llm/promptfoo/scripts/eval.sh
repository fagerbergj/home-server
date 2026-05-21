#!/usr/bin/env bash
# Run promptfoo evals against the llm-swap stack.
# Per-model rubric suites need the CPU judge: docker compose --profile judge up -d llm-judge
#
# Usage (run from anywhere — the script cd's to the promptfoo root):
#   ./scripts/eval.sh                                   # all models, default suites, + A/B compare
#   ./scripts/eval.sh qwen3.6-35b                       # one model, all its suites
#   ./scripts/eval.sh gpt-oss-120b qwen3.6-35b ...      # several models (space-separated)
#   ./scripts/eval.sh --suite coding                    # one suite, all models
#   ./scripts/eval.sh --suite math qwen3.6-35b          # one suite, one model
#   ./scripts/eval.sh --tools [model ...]               # document-pipeline routing (opt-in)
#   ./scripts/eval.sh --no-compare                      # skip the A/B compare phase
#
# Multiple positional args = a model allowlist. Compare still runs (it reads
# all providers from the compare config + cache), unless you pass exactly one
# model (a single-model compare is meaningless) or --no-compare.

set -euo pipefail
cd "$(dirname "$0")/.."   # promptfoo root — all paths below are relative to it

python3 - "$@" << 'EOF'
import sys, os, subprocess, yaml

CONFIG_FILE = 'eval-config.yaml'

# Suite name == config stem == test-file stem (configs/promptfooconfig.<s>.yaml,
# test-suites/<s>.yaml). config_for/tests_for derive the paths.
SUITES = {
    'architecture', 'coding', 'math', 'function-call', 'brain-twisters',
    'cruxeval', 'calibration', 'hard-reasoning', 'large-code', 'tools',
}
def config_for(s): return f'configs/promptfooconfig.{s}.yaml'
# Test path used by the compare phase — resolved relative to the compare config
# (which lives in configs/), hence the ../ prefix.
def tests_for(s):  return f'../test-suites/{s}.yaml'

# Suites worth A/B comparison: rubric-graded only. Deterministic suites
# (math, cruxeval, hard-reasoning, large-code, tools, function-call) already
# have an objective pass/fail — a "pick the best" judge adds noise there.
COMPARE_SUITES = {'architecture', 'coding', 'calibration', 'brain-twisters'}

args = sys.argv[1:]
suite_filter = None
do_compare = True

new_args = []
i = 0
while i < len(args):
    a = args[i]
    if a == '--tools':
        suite_filter = 'tools'
        do_compare = False
    elif a == '--suite':
        suite_filter = args[i + 1]
        i += 1
    elif a == '--no-compare':
        do_compare = False
    else:
        new_args.append(a)
    i += 1

# Positional args form a model allowlist (empty = all models).
model_filters = set(new_args)

config = yaml.safe_load(open(CONFIG_FILE))

unknown = model_filters - set(config['models'])
if unknown:
    print(f'Unknown model(s): {", ".join(sorted(unknown))}', file=sys.stderr)
    print(f'Available: {", ".join(config["models"])}', file=sys.stderr)
    sys.exit(1)

# Phase 1: per-model per-suite evals
suites_run = set()
for model, cfg in config['models'].items():
    if model_filters and model not in model_filters:
        continue
    concurrency = cfg['concurrency']
    suites = [suite_filter] if suite_filter else cfg['suites']

    for suite in suites:
        if suite not in SUITES:
            print(f'Unknown suite: {suite}', file=sys.stderr)
            continue
        print(f'\n{"═"*50}')
        print(f'  Suite: {suite:<16} Model: {model}  (×{concurrency})')
        print(f'{"═"*50}')
        env = {**os.environ, 'MODEL': model}
        subprocess.run(
            ['npx', 'promptfoo@latest', 'eval',
             '-c', config_for(suite),
             '--max-concurrency', str(concurrency),
             '--output', f'evals/{model}-{suite}.json'],
            env=env, check=False
        )
        suites_run.add(suite)

# Phase 2: blind A/B comparison. Skip for a single-model run (a select-best
# of one is meaningless). For all-models or a multi-model allowlist it runs —
# the compare config reads every provider from its own list + promptfoo cache.
if do_compare and len(model_filters) != 1:
    compare_targets = suites_run & COMPARE_SUITES if suites_run else COMPARE_SUITES
    if suite_filter and suite_filter in COMPARE_SUITES:
        compare_targets = {suite_filter}

    for suite in sorted(compare_targets):
        print(f'\n{"─"*50}')
        print(f'  A/B compare: {suite}')
        print(f'{"─"*50}')
        env = {**os.environ, 'COMPARE_TESTS_FILE': tests_for(suite)}
        subprocess.run(
            ['npx', 'promptfoo@latest', 'eval',
             '-c', 'configs/promptfooconfig.compare.yaml',
             '--max-concurrency', '4',
             '--output', f'evals/compare-{suite}.json'],
            env=env, check=False
        )

print('\nAll done. View: npx promptfoo@latest view')
EOF

bash scripts/summarize.sh
