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
#   ./scripts/eval.sh --no-cache [...]             # disable promptfoo's response cache
#   ./scripts/eval.sh --probe-context [model ...]  # speed gate: load each model and
#                                                  #   measure decode t/s vs the role floors
#
# Positional args form a model allowlist (empty = all models).
#
# Every run ends with a ROLE SPEED GATES table (median decode t/s vs the chat=50/
# implementer=30/planner=15 floors). `--probe-context` actively loads each model
# and measures decode t/s directly (context fit is handled by the llm-swap config).

set -euo pipefail
cd "$(dirname "$0")/.."   # promptfoo root — all paths below are relative to it

# Clean up agentic sandbox containers on exit/interrupt. The provider removes
# them on per-test timeout/error, but Ctrl+C mid-run kills node before that
# cleanup fires, leaving named oc-agent/oc-grade containers detached (their
# opencode keeps hammering llm-swap). NB: removes ALL oc-* containers, so don't
# run two evals concurrently.
_cleanup_oc() { docker ps -aq --filter name=oc-agent --filter name=oc-grade 2>/dev/null | xargs -r docker rm -f >/dev/null 2>&1 || true; }
trap _cleanup_oc EXIT
trap '_cleanup_oc; exit 130' INT TERM

# The judge swaps onto the GPU for the batched grading phase; the first grading
# call absorbs that model load, so raise the per-request timeout from promptfoo's
# 300000ms (5 min) default to 10 min.
export REQUEST_TIMEOUT_MS="${REQUEST_TIMEOUT_MS:-600000}"

# --no-cache disables promptfoo's response cache (agent + repo tasks are
# nondeterministic — pass it for a guaranteed-fresh run). Strip it here so the
# python arg parser below only sees suite/model args.
args=()
for a in "$@"; do
  if [ "$a" = "--no-cache" ]; then export PROMPTFOO_CACHE_ENABLED=false
  elif [ "$a" = "--probe-context" ]; then export PROBE_CONTEXT=1
  else args+=("$a"); fi
done
if [ "${#args[@]}" -gt 0 ]; then set -- "${args[@]}"; else set --; fi

python3 - "$@" << 'EOF'
import sys, os, subprocess, yaml

CONFIG_FILE = 'eval-config.yaml'

# Suite name == config stem == test-file stem (configs/promptfooconfig.<s>.yaml,
# test-suites/<s>.yaml). config_for derives the path.
SUITES = {
    'architecture', 'coding', 'math', 'chat', 'brain-twisters',
    'cruxeval', 'calibration', 'hard-reasoning', 'agentic', 'chat-multiturn', 'tools',
    'livecodebench', 'code-review', 'clarify', 'structured', 'honesty',
    'coding-flow', 'chat-flow', 'summarize', 'bfcl', 'tests-for-diff', 'longbench',
    'terminal', 'judge',
}
def config_for(s): return f'configs/promptfooconfig.{s}.yaml'

# Role gates (from llm/MODEL_SELECTION.md). A model below a role's t/s floor OR
# whose context can't reach the role's window is disqualified FOR THAT ROLE —
# with a 10% tolerance (within 10% of a limit counts as a pass).
#   tps = min decode tok/s ; ctx = required context window (tokens)
ROLE_GATES = {
    'chat':        {'tps': 50, 'ctx': 32768},
    'implementer': {'tps': 30, 'ctx': 198000},
    'planner':     {'tps': 15, 'ctx': 132000},
}
TOL = 0.10  # within 10% of a floor/window is acceptable

def _median(xs):
    xs = sorted(xs); return xs[len(xs)//2] if xs else 0.0

def model_decode_tps(model):
    """Median decode t/s across a model's eval JSONs (eval-prompt context)."""
    import glob, json
    tps = []
    for f in glob.glob(f'evals/{model}-*.json'):
        try:
            d = json.load(open(f))
            res = d['results']['results'] if isinstance(d, dict) else d[0]['results']['results']
        except Exception:
            continue
        for r in res:
            tok = (r.get('response', {}).get('tokenUsage', {}) or {}).get('completion')
            lat = r.get('latencyMs')
            if tok and lat:
                tps.append(tok / (lat / 1000))
    return _median(tps), len(tps)

def speed_gate_report(models):
    print(f'\n{"═"*60}\n  ROLE SPEED GATES — median decode t/s vs floor\n{"═"*60}')
    for m in models:
        mt, n = model_decode_tps(m)
        cells = '  '.join(
            f"{role}:{'PASS' if mt >= g['tps'] * (1 - TOL) else 'FAIL'}(>={g['tps']})"
            for role, g in ROLE_GATES.items())
        print(f"  {m:<16} {mt:6.1f} t/s (n={n:>3})   {cells}")
    print("  NOTE: measured at small eval prompts. Run `--probe-context` for an")
    print("  actively-measured decode t/s (loads each model fresh).")

def context_probe(models):
    """Load each model and measure raw decode t/s vs the role floors. Context fit
    is set by the llm-swap config now — the model is served at its role window, so
    loading allocates the full KV and an OOM shows up here as a load failure; this
    only measures speed. A warmup call absorbs the model swap/load, so the timed
    call hits a warm model and short-prompt prefill ≈ pure decode."""
    import urllib.request, json, time
    URL = os.environ.get('LLM_SWAP_URL', 'http://127.0.0.1:11436/v1') + '/chat/completions'
    def call(m, max_tokens):
        body = json.dumps({'model': m, 'temperature': 0, 'max_tokens': max_tokens,
                           'messages': [{'role': 'user',
                               'content': 'Write a detailed 400-word explanation of how a CPU cache works.'}]}).encode()
        t0 = time.time()
        req = urllib.request.Request(URL, data=body, headers={'Content-Type': 'application/json'})
        d = json.load(urllib.request.urlopen(req, timeout=1800))
        ct = (d.get('usage') or {}).get('completion_tokens', 0) or 1
        return ct, time.time() - t0
    print(f'\n{"═"*60}\n  SPEED PROBE — decode t/s vs role floors\n{"═"*60}')
    for m in models:
        try:
            call(m, 1)              # warmup: absorb the model load/swap
            ct, dt = call(m, 512)   # measured: short prompt → dt ≈ decode time
            tps = ct / dt if dt else 0
            cells = '  '.join(
                f"{role}:{'PASS' if tps >= g['tps'] * (1 - TOL) else 'FAIL'}(>={g['tps']})"
                for role, g in ROLE_GATES.items())
            print(f"  {m:<16} {tps:6.1f} t/s ({ct} tok)   {cells}")
        except Exception as e:
            print(f"  {m:<16} FAILED ❌  {str(e)[:70]}")

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

selected = [m for m in config['models'] if not model_filters or m in model_filters]

# --probe-context: skip the suites, just check context-fit + t/s at each role window.
if os.environ.get('PROBE_CONTEXT'):
    context_probe(selected)
    sys.exit(0)

for model in selected:
    cfg = config['models'][model]
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
speed_gate_report(selected)
EOF

bash scripts/summarize.sh
