#!/usr/bin/env bash
# Generate RESULTS.md from eval JSON files in evals/.
# Called automatically by eval.sh after each run.
# Usage: ./summarize.sh

set -euo pipefail

python3 - << 'EOF'
import json, glob, os, datetime, statistics

files = sorted(glob.glob('evals/*.json'))
if not files:
    print("No eval results found in evals/")
    exit(0)

VALID_SUITES = ['architecture','coding','math','function-call','brain-twisters','tools']

def parse_name(name):
    # Match longest suite suffix first so 'brain-twisters' wins over 'twisters'
    for suite in sorted(VALID_SUITES, key=len, reverse=True):
        if name.endswith('-' + suite):
            return name[:-len(suite)-1], suite
    return None, None

# Parse results
# data: model -> suite -> {pass, total, errors, tps (list of per-test tok/s)}
data = {}
for f in files:
    name = os.path.basename(f).replace('.json', '')
    model, suite = parse_name(name)
    if model is None:
        continue
    try:
        d = json.load(open(f))
        results = d.get('results', {}).get('results', [])
        passed = sum(1 for r in results if r.get('success'))
        errors = sum(1 for r in results if r.get('error'))
        total = len(results)

        # Extract tok/s per test. Prefer llama.cpp's `timings.predicted_per_second`
        # (decode-only, excludes prompt eval). Fall back to tokenUsage/latencyMs.
        tps_values = []
        for r in results:
            resp = r.get('response', {}) or {}
            # Try cached raw response → timings.predicted_per_second
            tps = None
            raw = resp.get('raw') or resp.get('metadata', {}).get('raw') if isinstance(resp.get('metadata'), dict) else None
            if isinstance(raw, str):
                try:
                    raw = json.loads(raw)
                except Exception:
                    raw = None
            if isinstance(raw, dict):
                t = raw.get('timings')
                if isinstance(t, dict):
                    tps = t.get('predicted_per_second')
            # Fallback: tokenUsage + latencyMs
            if tps is None:
                usage = resp.get('tokenUsage') or {}
                completion = usage.get('completion') or usage.get('completionTokens')
                latency_ms = r.get('latencyMs')
                if completion and latency_ms and latency_ms > 0:
                    tps = completion / (latency_ms / 1000)
            if tps and tps > 0:
                tps_values.append(tps)

        data.setdefault(model, {})[suite] = {
            'pass': passed,
            'total': total,
            'errors': errors,
            'tps': statistics.median(tps_values) if tps_values else None,
        }
    except Exception:
        pass

if not data:
    print("No suite results found.")
    exit(0)

all_suites = ['architecture', 'coding', 'function-call', 'brain-twisters', 'math', 'tools']
suites = [s for s in all_suites if any(s in m for m in data.values())]
models = sorted(data.keys())

# Build markdown
lines = []
lines.append("# Eval Results\n")
lines.append(f"*Last updated: {datetime.date.today()}*\n")

# Header
header = "| Model | " + " | ".join(suites) + " |"
sep = "| --- | " + " | ".join("---" for _ in suites) + " |"
lines.append(header)
lines.append(sep)

for model in models:
    row = f"| {model} |"
    for suite in suites:
        r = data.get(model, {}).get(suite)
        if r is None:
            row += " — |"
        elif r['errors'] > 0 and r['pass'] == 0:
            row += f" ❌ {r['errors']} err |"
        else:
            pct = round(100 * r['pass'] / r['total']) if r['total'] else 0
            icon = "✅" if pct >= 80 else ("⚠️" if pct >= 60 else "❌")
            tps_str = f" {r['tps']:.0f}t/s" if r['tps'] else ""
            row += f" {icon} {r['pass']}/{r['total']} ({pct}%){tps_str} |"
    lines.append(row)

lines.append("")
lines.append("**Thresholds:** ✅ ≥80%  ⚠️ 60–79%  ❌ <60% or errors\n")
lines.append("**tok/s:** median decode speed across all tests in that suite\n")
lines.append("**Suites:** architecture (32) · coding (12) · function-call (11) · brain-twisters (9) · math (9) · tools (14)\n")

out = '\n'.join(lines)
with open('RESULTS.md', 'w') as f:
    f.write(out)
print(out)
print("\nWrote RESULTS.md")
EOF
