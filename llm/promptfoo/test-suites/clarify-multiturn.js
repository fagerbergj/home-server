// Custom promptfoo provider for the multi-turn clarify conversation.
//
// promptfoo's built-in simulated-user provider only runs the simulated user on
// promptfoo's hosted cloud models (the userProvider config field is declared but
// not wired up), which won't work against our local llm-swap. So we drive the
// loop ourselves, entirely on llm-swap:
//   turn 1  — model-under-test runs the clarify prompt on the digest, emits
//             <clarified_text>/<confidence>/<questions>
//   author  — the judge model (selene) plays the document author, answering the
//             model's questions using ONLY a ground-truth answer key
//   turn 2  — model-under-test revises with the answers in context
// Output is the full transcript so cross-turn asserts (fewer questions, higher
// confidence) and g-eval (final clarified_text uses the answers) can grade it.
//
// vars: system (clarify instruction), digest (the document), answer_key (facts).
// config: model (from {{env.MODEL}}), judge (default 'selene').
const URL = process.env.LLM_SWAP_URL || 'http://localhost:11436/v1';

async function chat(model, messages) {
  const res = await fetch(`${URL}/chat/completions`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer llm-swap' },
    body: JSON.stringify({ model, messages, max_tokens: 8192 }),
  });
  if (!res.ok) throw new Error(`llm-swap ${model} HTTP ${res.status}: ${await res.text()}`);
  const j = await res.json();
  return { content: j.choices?.[0]?.message?.content || '', usage: j.usage || {} };
}

class ClarifyMultiturnProvider {
  constructor(options) { this.config = (options && options.config) || {}; }
  modelName() { return this.config.model || process.env.MODEL || 'unknown'; }
  id() { return `clarify-multiturn:${this.modelName()}`; }

  async callApi(_prompt, context) {
    const v = (context && context.vars) || {};
    const model = this.modelName();
    const judge = this.config.judge || 'selene';
    const system = v.system, digest = v.digest, answerKey = v.answer_key;

    const usages = [];
    const acc = (u) => usages.push(u);

    // Turn 1: model runs clarify on the digest.
    const t1 = await chat(model, [
      { role: 'system', content: system },
      { role: 'user', content: digest },
    ]);
    acc(t1.usage);

    // Author: selene answers the model's questions from the ground-truth facts.
    const author = await chat(judge, [
      { role: 'system', content:
        'You are the author of the source document. Answer the assistant\'s ' +
        'clarifying questions using ONLY these ground-truth facts. If a question ' +
        'is not covered by the facts, say you do not know.\n\nFACTS:\n' + answerKey },
      { role: 'user', content:
        'The assistant produced this clarified draft and asked some clarifying ' +
        'questions:\n\n' + t1.content + '\n\nAnswer each question concisely.' },
    ]);
    acc(author.usage);

    // Turn 2: model revises with the answers in conversation context.
    const t2 = await chat(model, [
      { role: 'system', content: system },
      { role: 'user', content: digest },
      { role: 'assistant', content: t1.content },
      { role: 'user', content:
        'Here are my answers to your clarifying questions. Produce a final, ' +
        'updated clarified version that incorporates them. Do not ask these ' +
        'questions again.\n\n' + author.content },
    ]);
    acc(t2.usage);

    const transcript =
      '=== TURN 1 (model) ===\n' + t1.content +
      '\n\n=== AUTHOR ANSWERS (ground truth) ===\n' + author.content +
      '\n\n=== TURN 2 (model, final) ===\n' + t2.content;

    const sum = (k) => usages.reduce((n, u) => n + (u[k] || 0), 0);
    return {
      output: transcript,
      tokenUsage: {
        prompt: sum('prompt_tokens'),
        completion: sum('completion_tokens'),
        total: sum('total_tokens'),
      },
      metadata: { turns: 2 },
    };
  }
}

module.exports = ClarifyMultiturnProvider;
