#!/usr/bin/env bash
# Generate a timestamped results file evals/results-<YYYY-MM-DD-HHMM>.md (per-model
# pass/fail) from eval JSON files in evals/. With --compare, also write
# evals/compare-<YYYY-MM-DD-HHMM>.md (blind A/B win matrix) from the compare-*.json
# files. Timestamped filenames mean each run produces a fresh file instead of
# overwriting a tracked one. eval.sh calls it without --compare (results only);
# compare.sh calls it with --compare.
# Usage: ./scripts/summarize.sh [--compare]   (run from anywhere — cd's to root)

set -euo pipefail
cd "$(dirname "$0")/.."   # promptfoo root

python3 - "$@" << 'EOF'
import sys, json, glob, os, datetime, statistics, html
from collections import defaultdict

# The compare file (Phase 2) is only written when called with --compare (by
# compare.sh). A plain summarize / eval.sh run only writes the dated results file.
do_compare = '--compare' in sys.argv[1:]

files = sorted(glob.glob('evals/*.json'))
if not files:
    print("No eval results found in evals/")
    exit(0)

VALID_SUITES = ['architecture','coding','math','chat','brain-twisters',
                'cruxeval','calibration','hard-reasoning','agentic','chat-multiturn','tools',
                'judge']

def parse_name(name):
    """parse 'qwen3.6-35b-architecture' -> ('qwen3.6-35b', 'architecture').
    Returns (None, None) for compare-* or unknown names."""
    if name.startswith('compare-'):
        return None, None
    for suite in sorted(VALID_SUITES, key=len, reverse=True):
        if name.endswith('-' + suite):
            return name[:-len(suite)-1], suite
    return None, None

def truncate(s, n=500):
    s = str(s or '').strip()
    return s if len(s) <= n else s[:n] + ' …'

# ── Phase 1: per-model results (RESULTS.md) ────────────────────────────────
data = {}  # model -> suite -> {pass, total, errors, tps, failures}
agentic = {}  # model -> [{tokens, turns, passed}] — for the agentic efficiency table
# tok/s persists across runs: a cached response reports no completion tokens, so a
# fully-cached re-run reuses the last fresh value instead of blanking it.
tps_cache = json.load(open('evals/.tps.json')) if os.path.exists('evals/.tps.json') else {}
for f in files:
    name = os.path.basename(f).replace('.json', '')
    model, suite = parse_name(name)
    if model is None:
        continue
    try:
        d = json.load(open(f))
        results = d.get('results', {}).get('results', [])
        passed = sum(1 for r in results if r.get('success'))
        errors = sum(1 for r in results if r.get('failureReason') == 2)
        total = len(results)

        tps_values = []
        failures = []
        for r in results:
            resp = r.get('response', {}) or {}
            tps = None
            raw = resp.get('raw') or (resp.get('metadata', {}).get('raw') if isinstance(resp.get('metadata'), dict) else None)
            if isinstance(raw, str):
                try: raw = json.loads(raw)
                except Exception: raw = None
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

            if r.get('failureReason') == 1:
                tc = r.get('testCase', {}) or {}
                desc = tc.get('description') or '(no description)'
                output = resp.get('output', '')
                g = r.get('gradingResult', {}) or {}
                reasons = []
                for c in g.get('componentResults', []) or []:
                    metric = (c.get('assertion', {}) or {}).get('metric') or ''
                    score = c.get('score')
                    reasons.append({'metric': metric, 'score': score,
                                    'reason': truncate(c.get('reason'), 500)})
                if not reasons:
                    reasons.append({'metric': '', 'score': None,
                                    'reason': truncate(g.get('reason'), 500)})
                failures.append({'desc': desc, 'output': truncate(output, 800),
                                 'reasons': reasons})

        key = f"{model}-{suite}"
        fresh_tps = statistics.median(tps_values) if tps_values else None
        if fresh_tps is not None:
            tps_cache[key] = fresh_tps
        data.setdefault(model, {})[suite] = {
            'pass': passed, 'total': total, 'errors': errors,
            'tps': tps_cache.get(key),
            'failures': failures,
        }
        if suite == 'agentic':
            rows = []
            for r in results:
                resp = r.get('response', {}) or {}
                md = resp.get('metadata', {}) or {}
                tu = resp.get('tokenUsage', {}) or {}
                rows.append({'tokens': tu.get('total'), 'turns': md.get('turns'),
                             'passed': bool(r.get('success')), 'mode': md.get('mode') or 'solo'})
            agentic[model] = rows
    except Exception:
        pass

json.dump(tps_cache, open('evals/.tps.json', 'w'), indent=2)

if data:
    suites = [s for s in VALID_SUITES if any(s in m for m in data.values())]
    models = sorted(data.keys())

    lines = [f"# Eval Results\n", f"*Last updated: {datetime.date.today()}*\n"]
    lines.append("| Model | " + " | ".join(suites) + " |")
    lines.append("| --- | " + " | ".join("---" for _ in suites) + " |")
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
    lines.append("")

    # ── Agentic efficiency: median tokens/turns over solved tasks, split by task
    # kind. Solo (write-from-scratch) and repo-scale tasks (bugfix/review/summary)
    # differ ~20x in tokens, so a single median would be meaningless. ──
    if agentic:
        def eff_table(title, kinds, blurb):
            if not any(r['mode'] in kinds for rows in agentic.values() for r in rows):
                return
            lines.append(f"## {title}\n")
            lines.append(blurb + "\n")
            lines.append("| Model | solved | median tokens | median turns |")
            lines.append("| --- | --- | --- | --- |")
            for model in sorted(agentic):
                rows = [r for r in agentic[model] if r['mode'] in kinds]
                if not rows:
                    continue
                solved = [r for r in rows if r['passed']]
                if solved:
                    toks = [s['tokens'] for s in solved if s['tokens'] is not None]
                    turns = [s['turns'] for s in solved if s['turns'] is not None]
                    mt = f"{int(statistics.median(toks)):,}" if toks else "—"
                    mu = f"{statistics.median(turns):g}" if turns else "—"
                    lines.append(f"| {model} | {len(solved)}/{len(rows)} | {mt} | {mu} |")
                else:
                    lines.append(f"| {model} | 0/{len(rows)} | — | — |")
            lines.append("")
        eff_table("Agentic efficiency — solo tasks", {'solo'},
                  "Write-from-scratch tasks; median over *solved* tasks — lower is more efficient.")
        eff_table("Agentic efficiency — repo tasks", {'seeded', 'review', 'summarize'},
                  "Real-repo bugfix / review / summary; median over *solved* tasks (tokens include the cached prompt).")

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
                lines.append(f"<summary>{html.escape(fail['desc'])}</summary>\n")
                lines.append(f"**Output:**\n")
                lines.append(f"<pre>{html.escape(fail['output'])}</pre>\n")
                lines.append(f"**Judge reasoning:**")
                for rsn in fail['reasons']:
                    score_str = f" (score: {rsn['score']:.2f})" if rsn['score'] is not None else ""
                    metric_str = f" *{rsn['metric']}*" if rsn['metric'] else ""
                    reason_text = ' '.join(str(rsn['reason']).split())
                    lines.append(f"-{metric_str}{score_str} {reason_text}")
                lines.append(f"\n</details>\n")
    if not any_failures:
        lines.append("*No failures — all tests passed.*")

    out_path = f"evals/results-{datetime.datetime.now():%Y-%m-%d-%H%M}.md"
    with open(out_path, 'w') as f:
        f.write('\n'.join(lines))
    print(f"Wrote {out_path}")

# ── Phase 2: A/B comparison (COMPARE.md) — only with --compare (compare.sh) ──
if not do_compare:
    exit(0)
compare_files = sorted(glob.glob('evals/compare-*.json'))
if not compare_files:
    print("No compare-*.json files; skipping COMPARE.md")
    exit(0)

def provider_id_to_model(pid):
    """openai:chat:qwen3.6-35b -> qwen3.6-35b"""
    return pid.split(':')[-1] if pid else '(unknown)'

# wins[suite][model] = count of times model won that suite's tests
wins = defaultdict(lambda: defaultdict(int))
# per_test[suite] = [{'desc': ..., 'winner': ..., 'reason': ...}]
per_test = defaultdict(list)
totals = defaultdict(int)  # suite -> total comparable tests

for f in compare_files:
    suite = os.path.basename(f).replace('compare-', '').replace('.json', '')
    try:
        d = json.load(open(f))
    except Exception:
        continue
    results = d.get('results', {}).get('results', [])

    # Group results by test case index — each test_idx has N entries (one per provider)
    by_test = defaultdict(list)
    for r in results:
        by_test[r.get('testIdx')].append(r)

    for test_idx, group in by_test.items():
        if not group:
            continue
        totals[suite] += 1
        desc = (group[0].get('testCase', {}) or {}).get('description') or f'test #{test_idx}'
        winner_r = next((r for r in group if r.get('success')), None)
        if winner_r:
            model = provider_id_to_model(winner_r.get('provider', {}).get('id') or '')
            wins[suite][model] += 1
            g = winner_r.get('gradingResult', {}) or {}
            per_test[suite].append({
                'desc': desc, 'winner': model,
                'reason': truncate(g.get('reason'), 200),
            })
        else:
            per_test[suite].append({'desc': desc, 'winner': '(no winner)', 'reason': ''})

# Build COMPARE.md
clines = [f"# Blind A/B Comparison\n", f"*Last updated: {datetime.date.today()}*\n"]
clines.append("Selene judge picked the best of all 4 models' anonymized responses on each prompt.\n")

# Suite table
all_models = sorted({m for s in wins.values() for m in s})
clines.append("## Win rate per suite\n")
clines.append("| Suite | " + " | ".join(all_models) + " |")
clines.append("| --- | " + " | ".join("---" for _ in all_models) + " |")
for suite in sorted(wins.keys()):
    total = totals[suite]
    row = f"| {suite} |"
    for m in all_models:
        n = wins[suite].get(m, 0)
        pct = round(100 * n / total) if total else 0
        row += f" {n}/{total} ({pct}%) |"
    clines.append(row)
clines.append("")

# Per-test winners — compact: a collapsible table per suite
clines.append("## Per-test winners\n")
for suite in sorted(per_test.keys()):
    clines.append(f"<details><summary>{suite}</summary>\n")
    clines.append("| Test | Winner |")
    clines.append("| --- | --- |")
    for entry in per_test[suite]:
        desc = str(entry['desc']).replace('|', '\\|')
        clines.append(f"| {desc} | {entry['winner']} |")
    clines.append("\n</details>\n")

cmp_path = f"evals/compare-{datetime.datetime.now():%Y-%m-%d-%H%M}.md"
with open(cmp_path, 'w') as f:
    f.write('\n'.join(clines))
print(f"Wrote {cmp_path}")
EOF
