// Deterministic grader for the tools suite. Uses real OpenAI tool calling:
// promptfoo sets `output` to the tool_calls array directly when the model's
// message.content is empty (which it is when `tool_choice: auto` triggers a
// tool). When the model returns plain text instead (e.g. asking a clarifying
// question), `output` is the content string.
//
// Source for the output-assignment logic: promptfoo
// src/providers/openai/chat.ts ~L631-650.
//
// Special case for llama-3.3-70b: llm-swap runs it with --skip-chat-parsing
// (workaround for llama.cpp PRs #20800 / #20806 — Llama 3.x tool-call parser
// 500s when the model emits raw {type, name, parameters} JSON without the
// <|python_tag|> prefix). With that flag, llama-server returns the model's
// raw output as `content` (a JSON string) and we parse it client-side here.

function tryParseInlineToolCall(s) {
  if (typeof s !== 'string') return null;
  const trimmed = s.trim();
  if (!trimmed.startsWith('{')) return null;
  let obj;
  try { obj = JSON.parse(trimmed); } catch { return null; }
  if (!obj || typeof obj !== 'object') return null;
  // Accept either {name, parameters/arguments} or {type:"function", name, parameters/arguments}
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

// Returns {call, source} so the grader can penalize malformed-format calls
// even when their routing logic is correct. source = "native" means a real
// tool_calls field; "inline" means we recovered a tool call from a content
// string (broken Llama 3.x format that breaks ADK in production); null call
// means no tool call (text response, e.g. a clarification request).
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

const hasFieldSyntax = (q) => /\b\w+:[^\s]/.test(q);

module.exports = (output, context) => {
  const check = context.vars.check;
  const { call, source } = extractCall(output);
  const tool = call ? call.function?.name : null;
  const args = parseArgs(call);
  const q = args.query || '';
  const field = args.field;
  const id = args.id;

  // Score 5 for a clean native tool call with correct routing.
  // Score 2 for an "inline" call recovered from malformed JSON content —
  // the model routed correctly but emitted the wrong wire format; ADK would
  // not see this as a tool call in production, so the test fails (threshold
  // is 4) but we differentiate the routing-correct-but-format-broken case
  // from a wholly-wrong tool choice.
  const fmtTag = source === 'inline' ? ' [PROD-BROKEN format]' : '';
  const result = (ok, why) => {
    if (!ok) return { pass: false, score: 0, reason: why };
    const score = source === 'inline' ? 2 : 5;
    return { pass: score >= 4, score, reason: `${why}${fmtTag}` };
  };
  const seen = call
    ? `tool=${tool} args=${JSON.stringify(args)}`
    : `no tool call (output=${typeof output === 'string' ? JSON.stringify(output.slice(0, 100)) : JSON.stringify(output).slice(0, 100)})`;

  switch (check) {
    case 'tag_query':
      return result(tool === 'search_documents' && /tags?:"?invoice"?/i.test(q), seen);

    case 'date_query':
      return result(tool === 'search_documents' && /date_month:"?2026-05"?/i.test(q), seen);

    case 'title_keyword':
      return result(tool === 'search_documents' && /quarterly|review/i.test(q), seen);

    case 'rag_topical':
      return result(tool === 'rag_search' && /machine\s*learning/i.test(q) && !hasFieldSyntax(q), seen);

    case 'rag_synthesis':
      return result(tool === 'rag_search' && /westbrook/i.test(q) && !hasFieldSyntax(q), seen);

    case 'series_quoted':
      return result(tool === 'search_documents' && /series:"Secret Campaign"/.test(q), seen);

    case 'title_quoted':
      return result(
        tool === 'search_documents' && /title:"[^"]*meeting[^"]*"/i.test(q),
        seen
      );

    case 'no_field_in_rag':
      if (tool === 'search_documents') return result(true, 'redirected to search_documents');
      if (tool === 'rag_search') return result(!hasFieldSyntax(q), seen);
      return result(false, seen);

    case 'no_empty_search':
      if (tool === 'search_documents') return result(q.trim().length > 0, seen);
      // Acceptable: no tool call (asked for clarification).
      return result(call === null, seen);

    case 'no_empty_get':
      if (tool === 'get_document') {
        const realId = typeof id === 'string' && id.length > 0 && !/placeholder|none|null|<.*>/i.test(id);
        return result(realId, seen);
      }
      return result(tool === 'search_documents' || call === null, seen);

    case 'update_summary':
      return result(
        tool === 'update_document' && field === 'summary' && id === 'abc-123',
        seen
      );

    case 'reject_invalid_field':
      if (tool === 'update_document' && field === 'embedding') return result(false, seen);
      return result(true, seen);

    case 'no_retry_after_reject':
      return result(tool !== 'update_document', seen);

    case 'search_before_get':
      return result(tool === 'search_documents', seen);

    default:
      return { pass: false, score: 0, reason: `unknown check: ${check}` };
  }
};
