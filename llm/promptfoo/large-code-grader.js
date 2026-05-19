// Grader for large-code suite. Model invokes write_file(path, content) — we
// extract content, pipe to large-code-runner.sh which writes solution.py,
// compiles + runs pytest.
//
// Promptfoo surfaces tool calls per src/providers/openai/chat.ts L631-650:
//   - content empty + tool_calls present  → output = tool_calls array
//   - content + tool_calls both present   → output = full message object
//   - otherwise                            → output = string
//
// Llama-3.3-70b runs with --skip-chat-parsing (workaround for llama.cpp PRs
// #20800 / #20806) and returns raw JSON in `content`. Parse that as a
// fallback tool call.
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

function tryParseInlineToolCall(s) {
  if (typeof s !== 'string') return null;
  const trimmed = s.trim();
  if (!trimmed.startsWith('{')) return null;
  let obj;
  try { obj = JSON.parse(trimmed); } catch { return null; }
  if (!obj || typeof obj !== 'object') return null;
  const name = obj.name || obj.function?.name;
  if (!name) return null;
  const argsObj = obj.parameters || obj.arguments || obj.function?.arguments || {};
  return {
    function: {
      name,
      arguments: typeof argsObj === 'string' ? argsObj : JSON.stringify(argsObj),
    },
  };
}

// Returns {call, source} so we can penalize malformed-format calls. A
// recovered "inline" call means the model emitted a non-canonical tool format
// that ADK would not see as a tool call in production — even if the code
// happens to pass pytest, the production agent loop is broken.
function extractCall(output) {
  if (Array.isArray(output)) {
    return { call: output[0] || null, source: 'native' };
  }
  if (output && typeof output === 'object' && Array.isArray(output.tool_calls)) {
    return { call: output.tool_calls[0] || null, source: 'native' };
  }
  const inline = tryParseInlineToolCall(output);
  if (inline) return { call: inline, source: 'inline' };
  return { call: null, source: null };
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

  const { call, source } = extractCall(output);
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
    const rawScore = r.total > 0 ? (r.passed / r.total) * 5 : 0;
    // Cap at 2 (below typical 4 threshold) when we recovered the write_file
    // call from malformed Llama 3.x content. The code may pass pytest, but
    // ADK would not see this as a tool call in production.
    const score = source === 'inline' ? Math.min(rawScore, 2) : rawScore;
    const tag = source === 'inline' ? ' [PROD-BROKEN format]' : '';
    return {
      pass: score >= threshold,
      score,
      reason: `${r.passed}/${r.total} pytest — ${r.reason}${tag}`,
    };
  } catch (e) {
    return { pass: false, score: 0, reason: `runner error: ${e.message}` };
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
};
