// Grader for large-code suite. Inline `type: javascript` in promptfoo runs in a
// sandboxed ESM context where `require` is undefined — so the runner must live
// in a file://-referenced module like this one.
//
// Reads test_name and pass_threshold from context.vars. Shells out to
// large-code-runner.sh, which returns JSON: {compile, passed, total, reason}.
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

module.exports = (output, context) => {
  const testName = context.vars.test_name;
  const threshold = Number(context.vars.pass_threshold);
  const timeoutMs = Number(context.vars.timeout_ms || 120000);

  const tmpDir = fs.mkdtempSync(`/tmp/eval-${testName}-`);
  try {
    const runner = path.join(process.cwd(), 'large-code-runner.sh');
    const raw = execSync(`bash ${runner} ${testName} ${tmpDir}`, {
      input: output,
      timeout: timeoutMs,
      maxBuffer: 10 * 1024 * 1024,
    }).toString();
    const r = JSON.parse(raw);
    if (!r.compile) {
      return { pass: false, score: 0, reason: `compile fail: ${r.reason}` };
    }
    const score = r.total > 0 ? (r.passed / r.total) * 5 : 0;
    return {
      pass: score >= threshold,
      score,
      reason: `${r.passed}/${r.total} pytest — ${r.reason}`,
    };
  } catch (e) {
    return { pass: false, score: 0, reason: `runner error: ${e.message}` };
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
};
