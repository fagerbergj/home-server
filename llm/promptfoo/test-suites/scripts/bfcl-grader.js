// Deterministic grader for the BFCL-style tool-calling suite. Reuses the
// tool_calls extraction approach from tools-grader.js but returns ALL calls
// (parallel-call tests need them). promptfoo sets `output` to the tool_calls
// array when message.content is empty; to a content string otherwise (e.g. the
// model asks a clarifying question or writes prose). 'inline' = a tool call
// recovered from a content string (a broken format some models emit).
//
// Covers the BFCL categories: simple, multiple (pick the right fn), parallel,
// irrelevance (no fn fits → no call), and missing-param (don't fabricate).

function tryParseInlineToolCall(s) {
  if (typeof s !== 'string') return null;
  const t = s.trim();
  if (!t.startsWith('{')) return null;
  let obj;
  try { obj = JSON.parse(t); } catch { return null; }
  const name = obj && (obj.name || (obj.function && obj.function.name));
  if (!name) return null;
  const a = obj.parameters || obj.arguments || (obj.function && obj.function.arguments) || {};
  return { function: { name, arguments: typeof a === 'string' ? a : JSON.stringify(a) } };
}

function extractCalls(output) {
  if (Array.isArray(output)) return output.filter(Boolean);
  if (output && typeof output === 'object' && Array.isArray(output.tool_calls)) {
    return output.tool_calls.filter(Boolean);
  }
  const inline = tryParseInlineToolCall(output);
  return inline ? [inline] : [];
}

function argsOf(c) {
  try {
    const r = c.function.arguments;
    return typeof r === 'string' ? JSON.parse(r) : (r || {});
  } catch { return {}; }
}

module.exports = (output, context) => {
  const check = context.vars.check;
  const calls = extractCalls(output);
  const names = calls.map((c) => c.function && c.function.name).filter(Boolean);
  const P = (reason) => ({ pass: true, score: 1, reason });
  const F = (reason) => ({ pass: false, score: 0, reason });

  switch (check) {
    case 'simple_weather': {
      if (names.length !== 1 || names[0] !== 'get_weather') return F(`expected 1 get_weather, got ${JSON.stringify(names)}`);
      const a = argsOf(calls[0]);
      return /paris/i.test(a.location || '') && /^c/i.test(String(a.unit || '').trim())
        ? P('get_weather(Paris, celsius)') : F(`args ${JSON.stringify(a)}`);
    }
    case 'select_currency': {
      const c = calls.find((x) => x.function.name === 'convert_currency');
      if (!c) return F(`expected convert_currency, got ${JSON.stringify(names)}`);
      const a = argsOf(c);
      return Number(a.amount) === 250 && /usd/i.test(a.from_currency || '') && /eur/i.test(a.to_currency || '')
        ? P('convert_currency(250, USD, EUR)') : F(`args ${JSON.stringify(a)}`);
    }
    case 'parallel_weather': {
      const w = calls.filter((x) => x.function.name === 'get_weather').map((x) => String(argsOf(x).location || '').toLowerCase());
      return w.length >= 2 && w.some((l) => l.includes('tokyo')) && w.some((l) => l.includes('london'))
        ? P('two get_weather (Tokyo, London)') : F(`get_weather locations: ${JSON.stringify(w)}`);
    }
    case 'irrelevance': {
      return calls.length === 0 ? P('correctly made no tool call') : F(`should not have called: ${JSON.stringify(names)}`);
    }
    case 'miss_param_flight': {
      const f = calls.find((x) => x.function.name === 'search_flights');
      if (!f) return P('no call — correctly asked for the missing origin/date');
      const a = argsOf(f);
      return (!a.origin || String(a.origin).trim() === '')
        ? P('called without fabricating an origin') : F(`fabricated origin=${a.origin}`);
    }
    case 'select_email': {
      const c = calls.find((x) => x.function.name === 'send_email');
      if (!c) return F(`expected send_email, got ${JSON.stringify(names)}`);
      const a = argsOf(c);
      const body = `${a.subject || ''} ${a.body || ''}`;
      return /alice@corp\.com/i.test(a.to || '') && /(3\s*pm|15:00|3:00)/i.test(body)
        ? P('send_email to alice, 3pm') : F(`args ${JSON.stringify(a)}`);
    }
  }
  return F(`unknown check ${check}`);
};
