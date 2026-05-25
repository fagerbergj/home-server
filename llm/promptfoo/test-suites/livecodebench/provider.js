// Custom promptfoo provider — LiveCodeBench code generation.
//
// Per test (= one pinned LCB problem) it generates a solution with the model
// under test via llm-swap, then grades it by EXECUTING against the problem's
// hidden tests inside a throwaway python:3.10-slim container (LCB venv at
// $LCB_HOME, mounted at /work; --network none during grading). Returns
// {passed,total} so a deterministic javascript assert decides pass/fail — no
// judge needed — plus tokenUsage for summarize.sh.
//
// Runs ON jason-server (docker + llm-swap local). Model comes from provider
// config.model (rendered from {{ env.MODEL }}). Requires the LCB runtime built
// by setup.sh (default ~/lcb-smoke: LiveCodeBench clone + /work-pinned venv +
// problems.json). The venv is path-pinned to /work, so we always mount there.
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const URL = process.env.LLM_SWAP_URL || 'http://localhost:11436/v1';
const LCB_HOME = process.env.LCB_HOME || path.join(os.homedir(), 'lcb-smoke');
const GEN_TIMEOUT_MS = (Number(process.env.LCB_GEN_TIMEOUT_S) || 900) * 1000;
const EXEC_TIMEOUT_S = Number(process.env.LCB_EXEC_TIMEOUT_S) || 6;
const MAX_TOKENS = Number(process.env.LCB_MAX_TOKENS) || 4096;

// eval_sample (the hidden test cases) is large, so it stays out of promptfoo
// vars — look it up here by question_id from the same pinned problems.json.
let SAMPLES = null;
function evalSampleFor(qid) {
  if (!SAMPLES) {
    const file = path.join(LCB_HOME, 'problems.json');
    let probs;
    try { probs = JSON.parse(fs.readFileSync(file, 'utf8')); }
    catch (e) { throw new Error(`problems.json missing at ${file} — run test-suites/livecodebench/setup.sh`); }
    SAMPLES = new Map(probs.map((p) => [p.question_id, p.eval_sample]));
  }
  return SAMPLES.get(qid);
}

function buildPrompt(v) {
  const sc = v.starter_code
    ? `\n\nUse this starter code:\n\`\`\`python\n${v.starter_code}\n\`\`\``
    : '';
  return 'Solve this competitive programming problem. Respond with a complete, correct '
    + 'Python solution in a single ```python code block.\n\n' + v.question_content + sc;
}

function extractCode(txt) {
  const m = [...txt.matchAll(/```(?:python)?\s*\n([\s\S]*?)```/g)];
  return m.length ? m[m.length - 1][1].trim() : txt.trim();
}

class LiveCodeBenchProvider {
  constructor(options) { this.config = (options && options.config) || {}; }
  modelName() { return this.config.model || process.env.MODEL || 'unknown'; }
  id() { return `livecodebench:${this.modelName()}`; }

  async callApi(prompt, context) {
    const v = (context && context.vars) || {};
    const model = this.modelName();
    const sample = evalSampleFor(v.question_id);
    if (!sample) return { error: `no eval_sample for ${v.question_id} in problems.json` };

    // 1. Generate.
    let content = '', tokenUsage = {};
    try {
      const r = await fetch(`${URL}/chat/completions`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          model,
          messages: [{ role: 'user', content: buildPrompt(v) }],
          max_tokens: MAX_TOKENS,
          temperature: 0.2,
        }),
        signal: AbortSignal.timeout(GEN_TIMEOUT_MS),
      });
      if (!r.ok) return { error: `llm-swap ${r.status}: ${(await r.text()).slice(0, 200)}` };
      const j = await r.json();
      content = j.choices?.[0]?.message?.content || '';
      const u = j.usage || {};
      tokenUsage = { prompt: u.prompt_tokens || 0, completion: u.completion_tokens || 0, total: u.total_tokens || 0 };
    } catch (e) {
      return { error: `generation failed: ${e.message}` };
    }
    const code = extractCode(content);

    // 2. Grade by execution in a throwaway container (network off).
    const io = fs.mkdtempSync(path.join(os.tmpdir(), 'lcb-'));
    let passed = 0, total = 1, reason = '';
    try {
      fs.writeFileSync(path.join(io, 'in.json'),
        JSON.stringify({ eval_sample: sample, code, timeout: EXEC_TIMEOUT_S }));
      let out = '';
      try {
        out = execFileSync('docker', [
          'run', '--rm', '--network', 'none',
          '--label', 'com.centurylinklabs.watchtower.enable=false',
          '-v', `${LCB_HOME}:/work`, '-v', `${__dirname}:/scripts`, '-v', `${io}:/io`,
          'python:3.10-slim', 'bash', '-c',
          '. /work/venv/bin/activate && PYTHONPATH=/work/LiveCodeBench python /scripts/grade_one.py /io/in.json',
        ], { timeout: 180000, maxBuffer: 16 * 1024 * 1024 }).toString();
      } catch (e) {
        out = (e.stdout || '').toString() + (e.stderr || '').toString();
      }
      const line = out.trim().split('\n').filter(Boolean).pop() || '{}';
      try {
        const g = JSON.parse(line);
        passed = g.passed || 0; total = g.total || 1; reason = `pass@1=${g.pass1}`;
      } catch (e) {
        reason = `grade parse fail: ${out.trim().slice(-200)}`;
      }
    } finally {
      try { execFileSync('rm', ['-rf', io]); } catch (e) { /* ignore */ }
    }

    return {
      output: JSON.stringify({ question_id: v.question_id, passed, total }),
      tokenUsage,
      metadata: { question_id: v.question_id, passed, total, reason, code_chars: code.length },
    };
  }
}

module.exports = LiveCodeBenchProvider;
