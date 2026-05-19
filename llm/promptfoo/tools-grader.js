// Deterministic grader for the tools suite. Uses real OpenAI tool calling:
// promptfoo sets `output` to the tool_calls array directly when the model's
// message.content is empty (which it is when `tool_choice: auto` triggers a
// tool). When the model returns plain text instead (e.g. asking a clarifying
// question), `output` is the content string.
//
// Source for the output-assignment logic: promptfoo
// src/providers/openai/chat.ts ~L631-650.

function extractCall(output) {
  // Case 1: array of tool_calls (content was empty)
  if (Array.isArray(output)) {
    return output[0] || null;
  }
  // Case 2: full message object with both content + tool_calls
  if (output && typeof output === 'object' && Array.isArray(output.tool_calls)) {
    return output.tool_calls[0] || null;
  }
  // Case 3: plain string — no tool call. Treated as "tool=null" intent.
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

const hasFieldSyntax = (q) => /\b\w+:[^\s]/.test(q);

module.exports = (output, context) => {
  const check = context.vars.check;
  const call = extractCall(output);
  const tool = call ? call.function?.name : null;
  const args = parseArgs(call);
  const q = args.query || '';
  const field = args.field;
  const id = args.id;
  const result = (ok, why) => ({ pass: ok, score: ok ? 5 : 0, reason: why });
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
