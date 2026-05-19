#!/usr/bin/env bash
# Run promptfoo evals against the llm-swap stack.
# Judge (llm-judge) must be running: make -C .. judge-up
#
# Usage:
#   ./eval.sh                              # all models, default suites, + A/B compare
#   ./eval.sh llama-3.3-70b               # one model, all its suites
#   ./eval.sh --suite coding              # one suite, all models
#   ./eval.sh --suite math qwen3.6-35b   # one suite, one model
#   ./eval.sh --tools [model]             # document-pipeline routing (opt-in)
#   ./eval.sh --no-compare                # skip the A/B compare phase

set -euo pipefail

python3 - "$@" << 'EOF'
import sys, os, subprocess, yaml

CONFIG_FILE = 'eval-config.yaml'
SUITE_CONFIG = {
    'architecture':   ('promptfooconfig.architecture.yaml',   'architecture-tests.yaml'),
    'coding':         ('promptfooconfig.coding.yaml',         'coding-tests.yaml'),
    'math':           ('promptfooconfig.math.yaml',           'math-tests.yaml'),
    'function-call':  ('promptfooconfig.function-call.yaml',  'function-call-tests.yaml'),
    'brain-twisters': ('promptfooconfig.brain-twisters.yaml', 'brain-twister-tests.yaml'),
    'cruxeval':       ('promptfooconfig.cruxeval.yaml',       'cruxeval-tests.yaml'),
    'calibration':    ('promptfooconfig.calibration.yaml',    'calibration-tests.yaml'),
    'hard-reasoning': ('promptfooconfig.hard-reasoning.yaml', 'hard-reasoning-tests.yaml'),
    'large-code':     ('promptfooconfig.large-code.yaml',     'large-code-tests.yaml'),
    'tools':          ('promptfooconfig.tools.yaml',          'tool-tests.yaml'),
}

# Suites that benefit from A/B comparison (subjective grading).
# Skip suites with deterministic grading (cruxeval, function-call, large-code)
# — A/B doesn't add info when the answer is right or wrong.
COMPARE_SUITES = {'architecture', 'calibration', 'hard-reasoning', 'brain-twisters'}

args = sys.argv[1:]
suite_filter = None
model_filter = None
do_compare = True

# Parse flags
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

if new_args:
    model_filter = new_args[0]

config = yaml.safe_load(open(CONFIG_FILE))

# Phase 1: Per-model per-suite evals
suites_run = set()
for model, cfg in config['models'].items():
    if model_filter and model != model_filter:
        continue
    concurrency = cfg['concurrency']
    suites = [suite_filter] if suite_filter else cfg['suites']

    for suite in suites:
        if suite not in SUITE_CONFIG:
            print(f'Unknown suite: {suite}', file=sys.stderr)
            continue
        cfgfile, _ = SUITE_CONFIG[suite]
        print(f'\n{"═"*50}')
        print(f'  Suite: {suite:<16} Model: {model}  (×{concurrency})')
        print(f'{"═"*50}')
        env = {**os.environ, 'MODEL': model}
        subprocess.run(
            ['npx', 'promptfoo@latest', 'eval',
             '-c', cfgfile,
             '--max-concurrency', str(concurrency),
             '--output', f'evals/{model}-{suite}.json'],
            env=env, check=False
        )
        suites_run.add(suite)

# Phase 2: Blind A/B comparison across all 4 models
if do_compare and not model_filter:
    compare_targets = suites_run & COMPARE_SUITES if suites_run else COMPARE_SUITES
    if suite_filter and suite_filter in COMPARE_SUITES:
        compare_targets = {suite_filter}

    for suite in sorted(compare_targets):
        _, tests_file = SUITE_CONFIG[suite]
        print(f'\n{"─"*50}')
        print(f'  A/B compare: {suite}')
        print(f'{"─"*50}')
        env = {**os.environ, 'COMPARE_TESTS_FILE': tests_file}
        subprocess.run(
            ['npx', 'promptfoo@latest', 'eval',
             '-c', 'promptfooconfig.compare.yaml',
             '--max-concurrency', '2',
             '--output', f'evals/compare-{suite}.json'],
            env=env, check=False
        )

print('\nAll done. View: npx promptfoo@latest view')
EOF

bash summarize.sh
