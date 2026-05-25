// LongBench-style long-context suite (generator). Each test builds a long filler
// document with planted "FACT" lines dispersed throughout, then asks an
// AGGREGATION question (sum of two dispersed codes) — a deterministic answer,
// judge-free. Tests at increasing lengths probe where comprehension degrades.
//
// Contamination-proof: generated at load time (never in training data). A doc
// longer than the model's -c errors out = a correct "doesn't fit" signal for the
// long ones (e.g. the ~180k test fails on a 128k-native model, passes on Qwen3.6's
// 256k). Aggregation (find 2 dispersed facts + add) is the 2026-hard variant, not
// solved needle-in-a-haystack.

function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const ANIMALS = ['otter', 'heron', 'marmot', 'viper', 'lynx', 'tapir', 'gannet', 'ibex', 'quokka', 'dingo'];
const COLORS = ['amber', 'cobalt', 'jade', 'crimson', 'slate', 'ochre', 'teal', 'mauve', 'russet', 'indigo'];
const FILLER = 'The quarterly logistics review noted no anomalies in the regional distribution network this cycle.';
const FILLER_TOK = 15; // rough tokens per filler line

function build(targetTokens, numFacts, seed) {
  const r = mulberry32(seed);
  const facts = [];
  const used = new Set();
  while (facts.length < numFacts) {
    const c = COLORS[Math.floor(r() * COLORS.length)];
    const a = ANIMALS[Math.floor(r() * ANIMALS.length)];
    const key = `${c} ${a}`;
    if (used.has(key)) continue;
    used.add(key);
    facts.push({ c, a, code: 1000 + Math.floor(r() * 9000) });
  }
  const factLines = facts.map((f) => `FACT: the ${f.c} ${f.a} has code ${f.code}.`);
  const lines = [];
  let tok = 0, fi = 0, since = 0;
  const gap = Math.max(1, Math.floor((targetTokens / (numFacts + 1)) / FILLER_TOK));
  while (tok < targetTokens) {
    lines.push(FILLER); tok += FILLER_TOK; since += 1;
    if (since >= gap && fi < factLines.length) { lines.push(factLines[fi++]); tok += 15; since = 0; }
  }
  while (fi < factLines.length) lines.push(factLines[fi++]);

  const i1 = Math.floor(r() * facts.length);
  let i2 = Math.floor(r() * facts.length);
  if (i2 === i1) i2 = (i2 + 1) % facts.length;
  const f1 = facts[i1], f2 = facts[i2];
  const question = `Using ONLY the FACT lines in the document above, what is the SUM of `
    + `the code for the ${f1.c} ${f1.a} and the code for the ${f2.c} ${f2.a}? `
    + `Answer with only the number.`;
  return { doc: lines.join('\n'), question, answer: String(f1.code + f2.code) };
}

const SIZES = [4000, 32000, 96000, 180000];
module.exports = SIZES.map((n, idx) => {
  const { doc, question, answer } = build(n, 8, 1234 + idx);
  return {
    description: `longbench: aggregation @ ~${Math.round(n / 1000)}k tokens`,
    vars: { doc, question },
    assert: [
      {
        type: 'javascript',
        // answer baked in; strip commas/whitespace and check the number appears
        value: `String(output).replace(/[,\\s]/g, '').includes(${JSON.stringify(answer)})`,
      },
    ],
  };
});
