// Custom promptfoo provider — tests-for-diff (A-7).
//
// Per test (= one fixture under fixtures/<case>/) it asks the model under test
// to WRITE a pytest suite for a given diff, then grades it by MUTATION TESTING:
// run the generated tests against the correct code (must PASS) and against each
// planted mutant (must FAIL = regression caught). Returns mutation_score so a
// deterministic js assert decides pass/fail — no judge.
//
// Fixture layout:  fixtures/<case>/{ diff.txt, correct.py, mutants/*.py }
// Runs ON jason-server. Model = provider config.model ({{ env.MODEL }}).
// Requires the tfd-runner image (test-suites/tests-for-diff/setup.sh).
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const URL = process.env.LLM_SWAP_URL || 'http://localhost:11436/v1';
const FIXTURES = path.join(__dirname, 'fixtures');
const GEN_TIMEOUT_MS = (Number(process.env.TFD_GEN_TIMEOUT_S) || 600) * 1000;
const MAX_TOKENS = Number(process.env.TFD_MAX_TOKENS) || 8192;

function buildPrompt(diff, correct) {
  return [
    'You are given a code change as a unified diff, and the current version of',
    'the module (subject.py) after the change. Write a THOROUGH pytest test suite',
    'for the behavior introduced or changed by this diff.',
    '',
    'Requirements:',
    '- Import the code under test from the module `subject` (e.g. `from subject import foo`).',
    '- Focus the tests on the NEW / CHANGED behavior so they would catch a regression in it.',
    '- Output ONLY the test code, in a single ```python code block.',
    '',
    '=== diff ===',
    diff,
    '',
    '=== subject.py (current, post-change) ===',
    correct,
  ].join('\n');
}

function extractCode(txt) {
  // Require a real fenced block — never return raw prose (gpt-oss dumps long
  // reasoning narrative that would parse as a broken "test file").
  const m = [...String(txt || '').matchAll(/```(?:python)?\s*\n([\s\S]*?)```/g)];
  return m.length ? m[m.length - 1][1].trim() : '';
}

class TestsForDiffProvider {
  constructor(options) { this.config = (options && options.config) || {}; }
  modelName() { return this.config.model || process.env.MODEL || 'unknown'; }
  id() { return `tests-for-diff:${this.modelName()}`; }

  async callApi(prompt, context) {
    const v = (context && context.vars) || {};
    const model = this.modelName();
    const dir = path.join(FIXTURES, v.case || '');
    if (!fs.existsSync(dir)) return { error: `fixture missing: ${dir}` };
    const diff = fs.readFileSync(path.join(dir, 'diff.txt'), 'utf8');
    const correct = fs.readFileSync(path.join(dir, 'correct.py'), 'utf8');

    // 1. Generate the test suite.
    let content = '', tokenUsage = {};
    try {
      const r = await fetch(`${URL}/chat/completions`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          model,
          messages: [{ role: 'user', content: buildPrompt(diff, correct) }],
          max_tokens: MAX_TOKENS, temperature: 0.2,
          // gpt-oss otherwise runs away enumerating test ideas in the reasoning
          // channel and never emits the final answer. Cap reasoning so it writes
          // the tests. (Non-gpt-oss models ignore this kwarg.)
          chat_template_kwargs: { reasoning_effort: 'low' },
        }),
        signal: AbortSignal.timeout(GEN_TIMEOUT_MS),
      });
      if (!r.ok) return { error: `llm-swap ${r.status}: ${(await r.text()).slice(0, 200)}` };
      const j = await r.json();
      const msg = j.choices?.[0]?.message || {};
      content = msg.content || '';
      // gpt-oss with --reasoning-format auto sometimes leaves `content` empty and
      // puts the code in reasoning_content — fall back to it if content has no block.
      this._reasoning = msg.reasoning_content || '';
      const u = j.usage || {};
      tokenUsage = { prompt: u.prompt_tokens || 0, completion: u.completion_tokens || 0, total: u.total_tokens || 0 };
    } catch (e) {
      return { error: `generation failed: ${e.message}` };
    }
    let testCode = extractCode(content);
    if (!testCode || testCode.length < 20) {
      const fromReasoning = extractCode(this._reasoning || '');
      if (fromReasoning && fromReasoning.length >= 20) testCode = fromReasoning;
    }
    if (!testCode || testCode.length < 20) {
      return { error: 'model returned no usable test code (empty content + reasoning)' };
    }

    // 2. Mutation-test in the container (network off — untrusted test code).
    const io = fs.mkdtempSync(path.join(os.tmpdir(), 'tfd-'));
    let result = { correct_pass: false, caught: 0, total: 0, mutation_score: 0 };
    let reason = '';
    try {
      fs.copyFileSync(path.join(dir, 'correct.py'), path.join(io, 'correct.py'));
      fs.mkdirSync(path.join(io, 'mutants'));
      for (const f of fs.readdirSync(path.join(dir, 'mutants'))) {
        fs.copyFileSync(path.join(dir, 'mutants', f), path.join(io, 'mutants', f));
      }
      fs.writeFileSync(path.join(io, 'test_subject.py'), testCode);
      let out = '';
      try {
        out = execFileSync('docker', [
          'run', '--rm', '--network', 'none',
          '--label', 'com.centurylinklabs.watchtower.enable=false',
          '-v', `${io}:/io`, '-v', `${__dirname}:/scripts`,
          'tfd-runner', 'python', '/scripts/run_mutation.py', '/io',
        ], { timeout: 180000, maxBuffer: 16 * 1024 * 1024 }).toString();
      } catch (e) {
        out = (e.stdout || '').toString() + (e.stderr || '').toString();
      }
      const line = out.trim().split('\n').filter(Boolean).pop() || '{}';
      try { result = JSON.parse(line); reason = `correct_pass=${result.correct_pass} mutants ${result.caught}/${result.total}`; }
      catch (e) { reason = `grade parse fail: ${out.trim().slice(-200)}`; }
    } finally {
      try { execFileSync('rm', ['-rf', io]); } catch (e) { /* ignore */ }
    }

    return {
      output: JSON.stringify(result),
      tokenUsage,
      metadata: { ...result, case: v.case, reason, test_chars: testCode.length },
    };
  }
}

module.exports = TestsForDiffProvider;
