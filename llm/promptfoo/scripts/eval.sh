#!/usr/bin/env bash
# Run promptfoo per-model evals against the llm-swap stack.
# Rubric suites use the GPU "selene" judge in the swap group: at concurrency 1
# promptfoo defers grading and batches all judge calls after generation, so
# Selene swaps in once per suite (one model→judge swap per suite, not per row).
# The blind A/B comparison is a separate step — see ./scripts/compare.sh.
#
# Usage (run from anywhere — the script cd's to the promptfoo root):
#   ./scripts/eval.sh                              # all models, their default suites
#   ./scripts/eval.sh qwen3.6-35b                  # one model, all its suites
#   ./scripts/eval.sh gpt-oss-120b qwen3.6-35b ... # several models (space-separated)
#   ./scripts/eval.sh --suite coding               # one suite, all models
#   ./scripts/eval.sh --suite math qwen3.6-35b     # one suite, one model
#   ./scripts/eval.sh --tools [model ...]          # document-pipeline routing (opt-in)
#
# Positional args form a model allowlist (empty = all models).

set -euo pipefail
cd "$(dirname "$0")/.."   # promptfoo root — all paths below are relative to it

# The judge swaps onto the GPU for the batched grading phase; the first grading
# call absorbs that model load, so raise the per-request timeout from promptfoo's
# 300000ms (5 min) default to 10 min.
export REQUEST_TIMEOUT_MS="${REQUEST_TIMEOUT_MS:-600000}"

python3 - "$@" << 'EOF'
import sys, os, subprocess, yaml

CONFIG_FILE = 'eval-config.yaml'

# Suite name == config stem == test-file stem (configs/promptfooconfig.<s>.yaml,
# test-suites/<s>.yaml). config_for derives the path.
SUITES = {
    'architecture', 'coding', 'math', 'chat', 'brain-twisters',
    'cruxeval', 'calibration', 'hard-reasoning', 'agentic', 'chat-multiturn', 'tools',
}
def config_for(s): return f'configs/promptfooconfig.{s}.yaml'

args = sys.argv[1:]
suite_filter = None

new_args = []
i = 0
while i < len(args):
    a = args[i]
    if a == '--tools':
        suite_filter = 'tools'
    elif a == '--suite':
        suite_filter = args[i + 1]
        i += 1
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

print('\nPer-model evals done. Run ./scripts/compare.sh for the A/B matrix.')
EOF

bash scripts/summarize.sh
