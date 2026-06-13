// Deterministic "judge the judge" grader. The provider output is a candidate
// judge's G-Eval verdict (JSON). This reproduces agent-researcher
// vetting/judge.go parseVerdict: recompute the overall score from the five
// criterion means, apply the two hard caps, derive passed (>= 0.7), then check
// that direction against the fixture's gold label.
//
// This is the cheap, objective half of the suite (no Selene needed). The
// llm-rubric assert in promptfooconfig.judge.yaml is the second, Selene-graded
// half that judges the QUALITY of the verdict's reasoning.
//
// Fixture vars consumed (see test-suites/judge.yaml):
//   gold_passed : boolean — should the answer clear the 0.7 gate?
//   gold_low    : ""      — or a criterion name that MUST be the failing one
//                          (its score should be <= 0.5)

const CRITERIA = ['grounded', 'no_fabrication', 'answers_question',
  'internally_consistent', 'cites_sources'];
const THRESHOLD = 0.7;

// Pull the first balanced {...} object out of the text and parse it, repairing a
// truncated tail by appending the missing close-braces (same tolerance as the Go
// parser, which appends "}" when the verdict is cut off at max_tokens).
function extractVerdict(text) {
  const start = text.indexOf('{');
  if (start < 0) return null;
  let depth = 0, end = -1, inStr = false, esc = false;
  for (let i = start; i < text.length; i++) {
    const c = text[i];
    if (esc) { esc = false; continue; }
    if (c === '\\') { esc = true; continue; }
    if (c === '"') { inStr = !inStr; continue; }
    if (inStr) continue;
    if (c === '{') depth++;
    else if (c === '}') { depth--; if (depth === 0) { end = i; break; } }
  }
  let body = end >= 0 ? text.slice(start, end + 1) : text.slice(start);
  for (let attempt = 0; attempt < 6; attempt++) {
    try { return JSON.parse(body); } catch (e) { body += '}'; }
  }
  return null;
}

function criterionScore(v, key) {
  const c = v && v.criteria && v.criteria[key];
  if (c == null) return null;
  const s = typeof c === 'object' ? c.score : c;
  return typeof s === 'number' ? s : null;
}

module.exports = (output, context) => {
  const vars = (context && context.vars) || {};
  const goldPassed = !!vars.gold_passed;
  const goldLow = (vars.gold_low || '').trim();

  const v = extractVerdict(String(output || ''));
  if (!v) {
    return { pass: false, score: 0, reason: 'verdict did not parse as JSON' };
  }

  const scores = CRITERIA.map((k) => criterionScore(v, k));
  if (scores.some((s) => s === null)) {
    const missing = CRITERIA.filter((k, i) => scores[i] === null);
    return { pass: false, score: 0, reason: `missing/invalid criteria: ${missing.join(', ')}` };
  }

  const mean = scores.reduce((a, b) => a + b, 0) / scores.length;
  let overall = mean;
  const cites = criterionScore(v, 'cites_sources');
  const fab = criterionScore(v, 'no_fabrication');
  if (cites === 0) overall = Math.min(overall, 0.40);
  if (fab === 0) overall = Math.min(overall, 0.35);
  const computedPassed = overall >= THRESHOLD;

  const reasons = [];
  let ok = true;

  if (computedPassed !== goldPassed) {
    ok = false;
    reasons.push(`direction WRONG: computed passed=${computedPassed} (score ${overall.toFixed(2)}), gold=${goldPassed}`);
  } else {
    reasons.push(`direction OK (passed=${computedPassed}, score ${overall.toFixed(2)})`);
  }

  if (goldLow) {
    const ls = criterionScore(v, goldLow);
    if (ls == null || ls > 0.5) {
      ok = false;
      reasons.push(`expected '${goldLow}' to fail (<=0.5) but it scored ${ls}`);
    } else {
      reasons.push(`flagged '${goldLow}'=${ls} ✓`);
    }
  }

  return { pass: ok, score: ok ? 1 : 0, reason: reasons.join('; ') };
};
