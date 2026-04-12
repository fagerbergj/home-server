# Model Evaluation (promptfoo)

Compares LLM models across coding, architecture decisions, and prompt engineering questions.

## Files

| File | Purpose |
|---|---|
| `promptfooconfig.yaml` | Local Ollama models, judged by Claude Sonnet |
| `promptfooconfig.cloud.yaml` | Cloud models (Sonnet/Haiku), judged by Prometheus2 |
| `tests.yaml` | All 36 test cases — shared by both configs |

## Quickstart

No install needed — run via `npx`. You need Node.js 18+.

```bash
node --version   # confirm 18+
```

If you don't have Node, install it via nvm:

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
nvm install --lts
```

## Running

### Local models (qwen35-coder, gemma4:31b, gemma4-26b)

Judged by Claude Sonnet. Requires `ANTHROPIC_API_KEY`.

```bash
cd llm/promptfoo
npx promptfoo@latest eval
```

Runs all 36 tests × 3 models sequentially (`maxConcurrency: 1`). Ollama automatically
evicts the previous model from VRAM when the next one loads. Expect it to take a while.

### Cloud calibration (Sonnet, Haiku)

Judged by Prometheus2 (local Ollama) to avoid Claude self-bias. Runs 2 tests at a time.

```bash
npx promptfoo@latest eval -c promptfooconfig.cloud.yaml
```

Requires Prometheus2 to be pulled in Ollama:

```bash
# One-time setup — creates a 28k-context variant
docker exec -it ollama sh -c 'printf "FROM tensortemplar/prometheus2:8x7b-Q3_K_S\nPARAMETER num_ctx 28672\n" | ollama create prometheus2-judge -f -'
```

### View results

```bash
npx promptfoo@latest view
```

### Filtering

Run a single test while iterating on a prompt:

```bash
npx promptfoo@latest eval --filter-pattern "Kafka"
```

Run one provider at a time:

```bash
npx promptfoo@latest eval --filter-providers "qwen35-coder"
```

## Calibration workflow

Before running local models, run the cloud calibration to validate rubrics:

1. `npx promptfoo@latest eval -c promptfooconfig.cloud.yaml`
2. Check results — **Sonnet should pass ≥90%, Haiku ≥70%**
3. If Sonnet fails a test, the prompt or rubric is too narrow — fix it before running local models
4. Haiku at 70% is the practical bar: a local model beating Haiku is meaningful signal

## Assertions

Tests are tiered by depth:

- `[baseline]` — fundamental knowledge; should always pass
- `[proficient]` — real understanding; distinguishes good from average
- `[expert]` — deep insight; changes how you think about the problem

## What to look for

**Decision/comparison questions** (REST server, Kafka vs RabbitMQ, etc.)
- Does it go beyond surface-level trade-offs?
- Does it explain what the answer *depends on*, not just pick a winner?
- Red flag: confident recommendations with no caveats, or hedging with no substance.

**Bug finding** (Go, Kotlin, TypeScript, SQL, Docker)
- Did it find all the bugs, or just the obvious one?
- Does it explain *why* each bug is a bug, not just flag it?
- Does the proposed fix actually work?

**Prompt engineering** (CoT, structured output, prompt chains)
- Does it show genuine understanding of LLM behaviour, or just repeat blog-post takes?

## Things that aren't meaningful signal

- Length — longer isn't better
- Formatting — nice headers don't mean correct content
- Confidence — a model that sounds sure isn't more likely to be right
