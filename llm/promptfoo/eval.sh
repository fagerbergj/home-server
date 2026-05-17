#!/usr/bin/env bash
# Run promptfoo evals against the llm-swap stack.
# Judge (llm-judge) must be running: make -C .. judge-up
#
# Usage:
#   ./eval.sh                             # all models, their default suites
#   ./eval.sh llama-3.3-70b              # one model, its default suites
#   ./eval.sh --suite coding             # one suite, all models
#   ./eval.sh --suite math qwen3.6-35b  # one suite, one model
#   ./eval.sh --tools [model]            # document-pipeline routing (opt-in)

set -euo pipefail

python3 - "$@" << 'EOF'
import sys, os, subprocess, yaml

CONFIG_FILE = 'eval-config.yaml'
SUITE_CONFIG = {
    'architecture':   'promptfooconfig.architecture.yaml',
    'coding':         'promptfooconfig.coding.yaml',
    'math':           'promptfooconfig.math.yaml',
    'function-call':  'promptfooconfig.function-call.yaml',
    'brain-twisters': 'promptfooconfig.brain-twisters.yaml',
    'tools':          'promptfooconfig.tools.yaml',
}

args = sys.argv[1:]
suite_filter = None
model_filter = None

if args and args[0] == '--tools':
    suite_filter = 'tools'
    args = args[1:]
elif args and args[0] == '--suite':
    suite_filter = args[1]
    args = args[2:]

if args:
    model_filter = args[0]

config = yaml.safe_load(open(CONFIG_FILE))

for model, cfg in config['models'].items():
    if model_filter and model != model_filter:
        continue
    concurrency = cfg['concurrency']
    if suite_filter:
        suites = [suite_filter]
    else:
        suites = cfg['suites']

    for suite in suites:
        cfgfile = SUITE_CONFIG.get(suite)
        if not cfgfile:
            print(f'Unknown suite: {suite}', file=sys.stderr)
            continue
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

print('\nAll done. View: npx promptfoo@latest view')
EOF
