# Model Evaluation (promptfoo)

Compares LLM models across coding, architecture decisions, and prompt engineering questions.

## Quickstart

No install needed — run via `npx`. You need Node.js 18+.

```bash
node --version   # confirm 18+
```

If you don't have Node, install it via your package manager:

```bash
# Ubuntu/Debian
sudo apt install nodejs npm

# or via nvm (recommended — lets you manage versions)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
nvm install --lts
```

Then verify promptfoo works:

```bash
npx promptfoo@latest --version
```

That's it — `npx` downloads and runs promptfoo on demand. No global install required.

## Running

```bash
cd llm/promptfoo
npx promptfoo@latest eval
```

This runs all prompts against both models sequentially — one model fully completes before the next loads, so they never compete for VRAM. Expect it to take a while.

Once done, open the results UI:

```bash
npx promptfoo@latest view
```

To run a single test while iterating on a prompt:

```bash
npx promptfoo@latest eval --filter-description "REST server"
```

## Judging the output

Claude Sonnet acts as the judge — it scores each response automatically using a rubric. Requires your Anthropic API key:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
npx promptfoo@latest eval
```

The eval table shows pass/fail per assertion. Use `promptfoo view` to read the full responses and judge's reasoning side by side.

### Switching to a local Ollama judge

The judge provider is a single line in `promptfooconfig.yaml`. To use a local model instead of Claude, change:

```yaml
defaultTest:
  assert:
    - type: llm-rubric
      provider: anthropic:claude-sonnet-4-6  # change this
```

The intended long-term approach is a promotion process: whichever model wins an eval run becomes the judge for the next contenders. To do that, update the provider line to point at the current champion before running the next eval.

A local judge works best with a large, capable model — smaller models tend to be inconsistent on nuanced rubrics. The bug-finding tests have explicit checklists in the rubric which are easier for smaller models to evaluate reliably than the open-ended trade-off rubrics.

### What to look for by category

**Decision/comparison questions** (REST server, Kafka vs RabbitMQ, etc.)
- Does it go beyond surface-level trade-offs, or just list bullet points you already knew?
- Does it tell you what *questions to ask yourself* rather than picking a winner?
- Does it acknowledge when the answer is "it depends" and actually explain what it depends on?
- Red flag: confident recommendations with no caveats, or hedging with no substance.

**Deep comparisons** (Go channels vs mutex, JWT vs sessions, etc.)
- Does it cover the non-obvious cases, or just repeat conventional wisdom?
- Does it give concrete examples where the "standard advice" would steer you wrong?
- Can it hold multiple trade-offs in tension without collapsing to a simple answer?

**Bug finding**
- Did it find all the bugs, or just the obvious one?
- Does it explain *why* each bug is a bug, not just flag it?
- Does the fix it proposes actually work, or introduce new issues?

**Structured output / prompt engineering**
- Does it show genuine understanding of LLM behaviour, or just repeat blog-post takes?
- Useful signal: does it distinguish between tasks where CoT helps vs. doesn't?

### A simple scoring approach

For each prompt, pick a winner or call it a tie. Track it in a tally:

| Prompt | Winner |
|--------|--------|
| REST server | qwen35-coder |
| Kafka vs RabbitMQ | tie |
| ... | ... |

After going through all prompts, patterns usually emerge — one model might be stronger on open-ended decisions while the other is more precise on code analysis.

### Things that aren't meaningful signal

- Length — longer isn't better
- Formatting — nice headers don't mean correct content
- Confidence — a model that sounds sure isn't more likely to be right
- Whether it agrees with your existing opinion
