// Deterministic grader for the tools suite. Tests output a JSON object of the
// shape {"tool": "...", "args": {...}, "reason": "..."} — we parse the last
// balanced JSON object in the response and check the routing.
//
// 8B judge models can't reliably grade structured output (judge confused
// `series:"Secret Campaign"` for "did not quote"), so we grade routing
// deterministically and skip the rubric entirely.
//
// Dispatch is by `vars.check`; each test names the check it wants.

function extractLastJson(output) {
  let depth = 0, end = -1, start = -1;
  for (let i = output.length - 1; i >= 0; i--) {
    const ch = output[i];
    if (ch === '}') {
      if (end === -1) end = i;
      depth++;
    } else if (ch === '{') {
      depth--;
      if (depth === 0 && end !== -1) { start = i; break; }
    }
  }
  if (start === -1) return null;
  try { return JSON.parse(output.substring(start, end + 1)); } catch { return null; }
}

const hasFieldSyntax = (q) => /\b\w+:[^\s]/.test(q);

module.exports = (output, context) => {
  const check = context.vars.check;
  const j = extractLastJson(output);
  if (!j) return { pass: false, score: 0, reason: 'no valid JSON object in output' };

  const tool = j.tool;
  const args = j.args || {};
  const q = args.query || '';
  const field = args.field;
  const id = args.id;
  const result = (ok, why) => ({ pass: ok, score: ok ? 5 : 0, reason: why });
  const seen = `tool=${JSON.stringify(tool)} args=${JSON.stringify(args)}`;

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
      // Acceptable: redirect to search_documents OR call rag_search without field:value.
      if (tool === 'search_documents') return result(true, 'redirected to search_documents');
      if (tool === 'rag_search') return result(!hasFieldSyntax(q), seen);
      return result(false, seen);

    case 'no_empty_search':
      // Must not call search_documents with empty query.
      if (tool === 'search_documents') return result(q.trim().length > 0, seen);
      // Acceptable: ask for clarification (tool=null) or any non-search tool.
      return result(tool === null, seen);

    case 'no_empty_get':
      // Must not call get_document with empty / placeholder id.
      if (tool === 'get_document') {
        const realId = typeof id === 'string' && id.length > 0 && !/placeholder|none|null|<.*>/i.test(id);
        return result(realId, seen);
      }
      // Acceptable: search first or ask.
      return result(tool === 'search_documents' || tool === null, seen);

    case 'update_summary':
      return result(
        tool === 'update_document' && field === 'summary' && id === 'abc-123',
        seen
      );

    case 'reject_invalid_field':
      // Must not accept field='embedding'.
      if (tool === 'update_document' && field === 'embedding') return result(false, seen);
      return result(true, seen);

    case 'no_retry_after_reject':
      return result(tool !== 'update_document', seen);

    case 'search_before_get':
      // First action must be search_documents (not get_document).
      return result(tool === 'search_documents', seen);

    default:
      return { pass: false, score: 0, reason: `unknown check: ${check}` };
  }
};
