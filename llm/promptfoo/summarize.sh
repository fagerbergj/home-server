#!/usr/bin/env bash
# Generate RESULTS.md from eval JSON files in evals/.
# Called automatically by eval.sh after each run.
# Usage: ./summarize.sh

set -euo pipefail

python3 - << 'EOF'
import json, glob, os, datetime

files = sorted(glob.glob('evals/*.json'))
if not files:
    print("No eval results found in evals/")
    exit(0)

# Parse results
data = {}  # model -> suite -> {pass, total}
for f in files:
    name = os.path.basename(f).replace('.json', '')
    parts = name.rsplit('-', 1)
    if len(parts) == 2 and parts[1] in ('architecture','coding','math','function-call','brain-twisters','tools'):
        model, suite = parts[0], parts[1]
    else:
        continue  # skip old/misc files
    try:
        d = json.load(open(f))
        results = d.get('results', {}).get('results', [])
        passed = sum(1 for r in results if r.get('success'))
        errors = sum(1 for r in results if r.get('error'))
        total = len(results)
        data.setdefault(model, {})[suite] = {'pass': passed, 'total': total, 'errors': errors}
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
lines.append(f"# Eval Results\n")
lines.append(f"*Last updated: {datetime.date.today()}*\n")

# Header
header = "| Model | " + " | ".join(f"{s}" for s in suites) + " |"
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
            row += f" {icon} {r['pass']}/{r['total']} ({pct}%) |"
    lines.append(row)

lines.append("")
lines.append("**Thresholds:** ✅ ≥80%  ⚠️ 60–79%  ❌ <60% or errors\n")
lines.append("**Suites:** architecture (32) · coding (12) · function-call (11) · brain-twisters (9) · math (9) · tools (14)\n")

out = '\n'.join(lines)
with open('RESULTS.md', 'w') as f:
    f.write(out)
print(out)
print("\nWrote RESULTS.md")
EOF
