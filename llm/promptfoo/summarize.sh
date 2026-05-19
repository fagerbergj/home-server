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

def truncate(s, n=500):
    s = str(s or '').strip()
    return s if len(s) <= n else s[:n] + ' …'

# data: model -> suite -> {pass, total, errors, tps, failures: [{desc, output, reasons}]}
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
        # failureReason: 1=assertion failure, 2=hard error.
        # `error` field is set for both, so it's not a reliable error indicator.
        errors = sum(1 for r in results if r.get('failureReason') == 2)
        total = len(results)

        tps_values = []
        failures = []
        for r in results:
            resp = r.get('response', {}) or {}

            # tok/s extraction
            tps = None
            raw = resp.get('raw') or (resp.get('metadata', {}).get('raw') if isinstance(resp.get('metadata'), dict) else None)
            if isinstance(raw, str):
                try:
                    raw = json.loads(raw)
                except Exception:
                    raw = None
            if isinstance(raw, dict):
                t = raw.get('timings')
                if isinstance(t, dict):
                    tps = t.get('predicted_per_second')
            if tps is None:
                usage = resp.get('tokenUsage') or {}
                completion = usage.get('completion') or usage.get('completionTokens')
                latency_ms = r.get('latencyMs')
                if completion and latency_ms and latency_ms > 0:
                    tps = completion / (latency_ms / 1000)
            if tps and tps > 0:
                tps_values.append(tps)

            # Collect failure details (assertion failures, not hard errors)
            if r.get('failureReason') == 1:
                tc = r.get('testCase', {}) or {}
                desc = tc.get('description') or '(no description)'
                output = resp.get('output', '')
                g = r.get('gradingResult', {}) or {}
                reasons = []
                # Include every component's judge reasoning + score; threshold
                # logic doesn't always reflect in component.pass, so include all.
                for c in g.get('componentResults', []) or []:
                    metric = (c.get('assertion', {}) or {}).get('metric') or ''
                    score = c.get('score')
                    reasons.append({
                        'metric': metric,
                        'score': score,
                        'reason': truncate(c.get('reason'), 500),
                    })
                if not reasons:
                    reasons.append({'metric': '', 'score': None, 'reason': truncate(g.get('reason'), 500)})
                failures.append({
                    'desc': desc,
                    'output': truncate(output, 800),
                    'reasons': reasons,
                })

        data.setdefault(model, {})[suite] = {
            'pass': passed,
            'total': total,
            'errors': errors,
            'tps': statistics.median(tps_values) if tps_values else None,
            'failures': failures,
        }
    except Exception:
        pass

if not data:
    print("No suite results found.")
    exit(0)

all_suites = ['architecture', 'coding', 'function-call', 'brain-twisters', 'math', 'tools']
suites = [s for s in all_suites if any(s in m for m in data.values())]
models = sorted(data.keys())

lines = []
lines.append("# Eval Results\n")
lines.append(f"*Last updated: {datetime.date.today()}*\n")

# Summary table
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
lines.append("**Thresholds:** ✅ ≥80%  ⚠️ 60–79%  ❌ <60% or errors")
lines.append("**tok/s:** median decode speed across all tests in that suite")
lines.append("**Suites:** architecture (32) · coding (12) · function-call (11) · brain-twisters (9) · math (9) · tools (14)")
lines.append("")

# Failures detail
lines.append("## Failures\n")
any_failures = False
for model in models:
    for suite in suites:
        r = data.get(model, {}).get(suite)
        if not r or not r.get('failures'):
            continue
        any_failures = True
        lines.append(f"### {model} — {suite} ({len(r['failures'])} failures)\n")
        for fail in r['failures']:
            lines.append(f"<details>")
            lines.append(f"<summary>{fail['desc']}</summary>\n")
            lines.append(f"**Output:**\n")
            lines.append(f"```\n{fail['output']}\n```\n")
            lines.append(f"**Judge reasoning:**")
            for rsn in fail['reasons']:
                score_str = f" (score: {rsn['score']:.2f})" if rsn['score'] is not None else ""
                metric_str = f" *{rsn['metric']}*" if rsn['metric'] else ""
                lines.append(f"-{metric_str}{score_str} {rsn['reason']}")
            lines.append(f"\n</details>\n")

if not any_failures:
    lines.append("*No failures — all tests passed.*")

out = '\n'.join(lines)
with open('RESULTS.md', 'w') as f:
    f.write(out)
print(f"Wrote RESULTS.md ({len(out)} bytes)")
EOF
