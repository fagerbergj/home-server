// Grader for large-code suite. Model invokes write_file(path, content) — we
// extract content, pipe to large-code-runner.sh which writes solution.py,
// compiles + runs pytest.
//
// Promptfoo surfaces tool calls per src/providers/openai/chat.ts L631-650:
//   - content empty + tool_calls present  → output = tool_calls array
//   - content + tool_calls both present   → output = full message object
//   - otherwise                            → output = string
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

function extractCall(output) {
  if (Array.isArray(output)) return output[0] || null;
  if (output && typeof output === 'object' && Array.isArray(output.tool_calls)) {
    return output.tool_calls[0] || null;
  }
  return null;
}

function parseArgs(call) {
  if (!call || !call.function) return {};
  const raw = call.function.arguments;
  if (typeof raw === 'string') {
    try { return JSON.parse(raw); } catch { return {}; }
  }
  return raw || {};
}

module.exports = (output, context) => {
  const testName = context.vars.test_name;
  const threshold = Number(context.vars.pass_threshold);
  const timeoutMs = Number(context.vars.timeout_ms || 120000);

  const call = extractCall(output);
  if (!call || call.function?.name !== 'write_file') {
    return {
      pass: false,
      score: 0,
      reason: `expected write_file tool call; got ${call ? call.function?.name : 'no tool call'}`,
    };
  }
  const args = parseArgs(call);
  if (typeof args.content !== 'string' || args.content.length === 0) {
    return { pass: false, score: 0, reason: 'write_file called without a content string' };
  }

  const tmpDir = fs.mkdtempSync(`/tmp/eval-${testName}-`);
  try {
    const runner = path.join(process.cwd(), 'large-code-runner.sh');
    const raw = execSync(`bash ${runner} ${testName} ${tmpDir}`, {
      input: args.content,
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
