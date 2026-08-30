# Model Selection

A decision framework for assigning local models to roles. The point of this doc:
decide **what we actually require**, check whether our **promptfoo suites measure
those requirements**, and only *then* score models against it. Aggregate eval
scores are not trusted until the coverage gaps below are understood.

Status: **draft — iterating on priorities.** Set the priority columns; everything
else keys off them.

---

## 1. Flows

Two independent flows. They do **not** need to be co-resident (they may swap).

- **Flow A — Coding agent:** plan + execute agentic loops for coding. **One
  flow** — internally a planning *facet* + an implementing *facet* (whether one
  model serves both or we split is TBD, §6). Concurrency: typically 1.
- **Flow B — Chat + pipeline:** all chat incl. interactive (OpenWebUI) + the
  quack agentic loops. **Must handle 2–4 concurrent** conversations
  / loops.

### Speed priority (fastest needed → slowest tolerated)

1. **Chat** — *fastest.* **Floor: ≥50 tok/s.** Interactive + 2–4 concurrent →
   **aggregate t/s**, per-stream t/s, and **TTFT** all matter.
2. **Coding implementer** — *fast.* **Floor: ≥30 tok/s.** Many edits per loop →
   **decode t/s**.
3. **Coding planner** — *slowest tolerated.* **Floor: ≥15 tok/s.** Called rarely,
   thinks deeply → **time-to-answer** is the only clock, and even that is loose.

These floors are **hard gates**: a model below the floor for a role is
disqualified *for that role* regardless of quality. Measured decode t/s (single
stream) is the yardstick; for **chat** the floor is per-stream **under 2–4
concurrent load**, not single-stream. Quick read against what we've measured:

| candidate (≈ decode t/s) | planner ≥15 | implementer ≥30 | chat ≥50 |
|---|:--:|:--:|:--:|
| gpt-oss-20b (~90) | ✅ | ✅ | ✅ (verify under load) |
| qwen3.6-35b (~62) | ✅ | ✅ | ✅ |
| gpt-oss-120b (~33–60) | ✅ | ✅ | ⚠️ borderline |
| minimax IQ2 (~47) | ✅ | ✅ | ⚠️ |
| qwen3.6-27b dense (~25–30?) | ✅ | ⚠️ borderline | ❌ |
| Llama-3.3-70B dense (~19) | ✅ | ❌ | ❌ |

(t/s are prior single-stream measurements / estimates — the bench confirms them.)

Implication: spend the speed levers (small quant, no CPU offload, KV quant,
speculative decoding, `--parallel`) on **chat first, implementer second**. The
planner is where we can afford a slow, heavy model.

### Context priority (most needed → least)

1. **Coding implementer** — **198k.** Reads files, changes files, runs bash,
   accumulates tool output over a long loop.
2. **Coding planner** — **132k.** Reads files + many tool descriptions; produces
   a plan, not a long edit trail.
3. **Chat** — **32k.** Reads and uses tools, but not whole repos.

These are **hard gates** (like the speed floors): a model whose native context <
the role's number is disqualified *for that role*, and it must also have the VRAM
to hold that much KV.

**The implementer's 198k is the binding constraint of the whole spec** — and it
collides with the ≥30 t/s floor (fast **and** huge context):

- **gpt-oss-120b / gpt-oss-20b are 128k-native → DISQUALIFIED as implementer**
  (128k < 198k). gpt-oss-120b at 131072 is also just under the planner's 132k.
- Only **≥198k-native** models qualify for implementer:
  - **Qwen3.6** — **262144 (256k) native** ✅, GQA (lighter KV), and 35B-A3B is
    fast (~62 t/s ≥ 30 floor) → **leading implementer candidate**. The 27B is
    256k too but ~25–30 t/s (speed-borderline).
  - **minimax-m2-reap** — 196k native (just under) + VRAM-hard KV.
- Then **VRAM for 198k KV** is the wall for the heavy ones. minimax is
  all-attention (~248 KiB/tok fp16): 198k ≈ **48 GB KV fp16 / ~24 GB q8 / ~12 GB
  q4**; with 41 GB IQ2 weights it fits **only with q4 KV** — a quality gamble on
  a 2-bit model. Qwen3.6 (GQA) holds 198k far more comfortably → another reason
  it leads the implementer slot.

So the implementer is now the hardest seat: **198k-native + 198k-KV-in-VRAM +
≥30 t/s.** The bench must measure each candidate's *real* max context (does it
load at 198k?) and the t/s there, not just quality.

---

## 2. Requirements rubric

Priority key: **P0** = hard requirement, **P1** = important, **P2** = nice to
have. Priorities below are a *proposal* — edit them. Three roles: **coding
planner** + **coding implementer** (Flow A), and **chat + pipeline** (Flow B).

### Flow A — Coding agent (one flow)

Planner and implementer are two *facets* of this single flow — the speed /
context spectra in §1 capture how their needs differ. Whether one model serves
both or we split is an open choice (§6), not two flows.

| #   | Requirement                                          | Why                              | Priority |
|-----|------------------------------------------------------|----------------------------------|:--------:|
| A1  | Plan / decompose a task (deep reasoning)             | drives the loop                  | P0 |
| A2  | Tool use (read / edit / run bash)                    | the loop *is* tool calls         | P0 |
| A3  | Generate **correct** code                            | output has to work               | P0 |
| A4  | Debug / comprehend existing code                     | most work is editing             | P0 |
| A5  | Honesty — no invented APIs; ground in authoritative sources | a wrong plan poisons everything | P0 |
| A6  | **Large context** (files, edits, bash output)        | implementer facet needs the most | P0 |
| A7  | Broad knowledge of many tools / libraries            | must know what's available       | P1 |
| A8  | Self-correct from tool results / errors              | loops fail without it            | P1 |
| A9  | Reliability over a long loop                         | no corruption / derail           | P1 |
| A10 | Speed: planner facet may be slow, implementer fast   | see §1 speed priority            | P1 |

### Flow B — Chat + pipeline
| #  | Requirement                          | Why                              | Priority |
|----|--------------------------------------|----------------------------------|:--------:|
| B1 | Structured output / schema adherence | pipeline breaks on bad JSON      | P0 |
| B2 | Tool calling (routing + args)        | pipeline routing                 | P0 |
| B3 | **Concurrency** (2–4, no OOM)        | stated hard requirement          | P0 |
| B4 | Summarize / classify / extract       | pipeline stages                  | P0 |
| B5 | Multi-turn coherence                 | interactive OpenWebUI            | P1 |
| B6 | World knowledge                      | interactive Q&A                  | P1/P2 |
| B7 | Honesty / calibration                | don't hallucinate in pipeline    | P1 |
| B8 | Per-stream speed + TTFT              | interactive feel under load      | P1 |

---

## 3. Suite coverage

Do the suites measure the rubric? (`✅` good · `🟡` partial/small-n · `❌` none)

Suites today: architecture(10), coding(5), chat(4), brain-twisters(9),
cruxeval(15), calibration(10), hard-reasoning(15), agentic(8), tools(14).
Disabled (saturated): chat-multiturn, math.

| Requirement                              | Suite(s)                                   | Coverage |
|------------------------------------------|--------------------------------------------|:--------:|
| Reasoning / planning (A1)                | hard-reasoning, brain-twisters, architecture | ✅ over-covered |
| Code debug / comprehend (A4)             | coding, cruxeval                           | ✅ |
| Tool calling (A2, B2)                    | tools                                      | ✅ |
| Calibration — admits "I don't know" (B7) | calibration                                | ✅ |
| Agentic loop / self-correct (A8, A9)     | agentic                                    | 🟡 on-point but small (8) |
| Summarize / classify / extract (B4)      | chat                                       | 🟡 small (4) |
| Code **generation** correctness (A3)     | agentic-bugfix only                        | 🟡 no "write code → run tests" |
| Structured-output **validity** (B1)      | tools / chat (implicit)                    | 🟡 weak — confirm it asserts schema |
| World knowledge (B6)                      | hard-reasoning (science)                   | 🟡 narrow |
| Coding: no invented APIs / details (A5)  | calibration (adjacent, not direct)         | 🟡 not tested directly |
| Multi-turn (B5)                          | chat-multiturn                             | ❌ disabled (saturated) |
| Long-context (A6)                        | —                                          | ❌ none (prompts are short) |
| Coding: grounding in authoritative sources (A5) | —                                   | ❌ none |
| TTFT / time-to-answer w/ thinking (A10, B8) | —                                       | ❌ not measured |
| Concurrency (B3)                         | VRAM budget (math, §4)                     | ✅ by design — no eval needed |

**Takeaway:** ~59 of ~80 tests measure single-turn reasoning & knowledge ("is
this a smart generalist") — the dimension we care about *least*. The suites that
target orchestration (agentic 8, tools 14, chat 4) are the *smallest*.
Concurrency (B3) we validate on paper via VRAM budgeting — no eval needed. The
real remaining eval gaps are P0/P1 **capabilities**: coding source-grounding and
honesty-vs-invented-APIs (A5), long-context (A6), multi-turn (B5), codegen
correctness (A3), and structured-output validity (B1). Ranking models by
aggregate score would over-index on smarts and miss these.

---

## 4. Proposed eval changes

Two options, not mutually exclusive:

1. **Reweight** — trust agentic / tools / chat; discount the reasoning bulk when
   scoring for these flows.
2. **Add coverage** for the capability gaps. Highest-leverage additions:
   - **Structured-output suite** — validate JSON / schema conformance directly.
     (covers B1; first verify whether `tools`/`chat` already assert this)
   - **Long-context suite** — large file / repo input. (covers A6)
   - **Grounding / honesty** — obscure or non-existent APIs; reward "I don't know
     / let me look it up", penalize invented details. (covers A5)
   - **Re-enable multi-turn** with harder cases. (covers B5)
   - **Codegen-correctness** — write code, execute against tests. (covers A3)

**Concurrency (B3) is not an eval** — validate on paper: does
`weights + N × KV(context) + compute buffer` fit in 64 GiB for the chat model at
N = 2–4? If the math fits, it works; batching doesn't change output quality.

---

## 5. tok/s — the four speeds and the levers

Requirements care about *different* speeds — don't conflate them:

- **Decode t/s** — generation speed (memory-bandwidth bound). Interactive feel, batch.
- **Prefill t/s** — prompt ingestion (compute bound). TTFT on long prompts/repos.
- **Time-to-answer** — includes *thinking tokens* before the reply. A 50 t/s model
  that thinks for 2000 tokens feels slower than a 30 t/s one that doesn't.
- **Aggregate t/s** — total across concurrent streams. The 2–4 concurrent requirement.

| Lever                              | Effect                          | Magnitude | Tradeoff |
|------------------------------------|---------------------------------|-----------|----------|
| Smaller quant                      | ↑ decode                        | large     | quality (esp. <Q4) |
| Fewer active params (model/MoE-A)  | ↑ decode                        | large     | capability |
| Drop CPU offload (`-ncmoe`↓)       | ↑ decode *if it fits*           | large     | needs VRAM |
| KV quant (`--cache-type q8_0`)     | ↑ decode @ long ctx, frees VRAM | med       | tiny quality |
| Tensor vs layer split              | tensor ↑ decode (~1.5×)         | med       | crashes some models, AllReduce overhead |
| Speculative decoding (draft model) | ↑ decode 1.5–3×                 | large     | VRAM for draft, build support, acceptance-dependent |
| Flash attn (`-fa on`)              | ↑ decode + prefill @ ctx        | med       | already on |
| `-ub`/`-b` larger                  | ↑ **prefill**                   | med       | compute-buffer VRAM |
| Prompt cache / KV reuse            | ↑ effective (skip reprocessing) | large for loops | — |
| `--parallel N` + cont. batching    | ↑ **aggregate**                 | large     | per-stream share ↓, KV VRAM |
| Shorter `-c`                       | ↑ decode slightly, frees VRAM   | small     | less context |
| Reasoning effort ↓ / thinking off  | ↑ **time-to-answer**            | very large (thinking models) | less deliberation |
| Optimized build (native/LTO)       | ↑ a few %                       | small     | maintain custom image |

Underused on this stack and worth a real look: **speculative decoding** (tiny
draft in front of a big target — potentially the single biggest decode win for
slow models) and **reasoning-effort control** (cheapest "make it feel fast" knob,
costs no VRAM). **Prompt-cache** is disproportionately large for *agentic loops*,
which reuse the same long context every turn.

### Tensor vs layer split (the consequential one)

Only matters for models that span **both** GPUs (>32 GiB). Single-GPU models
(e.g. a small chat model) skip it — and free the second GPU.

|              | decode            | KV-quant / context        | robustness                  |
|--------------|-------------------|---------------------------|-----------------------------|
| **tensor**   | ~1.5× faster (19.1 vs 12.5 t/s on a 70B) | ❌ incompatible → more KV VRAM, less ctx | crashes some archs (MiniMax); needs `-fit off` |
| **layer**    | baseline          | ✅ works → more context    | always works                |

- **Layer** (`--split-mode layer`, default): whole layers spread across GPUs,
  one active at a time. No parallel speedup, but robust and KV-quant works.
- **Tensor** (`--split-mode tensor`): every layer split row-wise across both
  GPUs + AllReduce (over PCIe here, so <2× gain). Faster decode, but no KV-quant
  and fragile on some architectures.

**It's speed vs (context + robustness)** — and that collides with the
implementer, which wants the *most* context **and** to be fast. Tensor buys
speed but caps context; layer buys context (via KV-quant) but costs speed. For a
both-GPU implementer this is the hardest single knob, and it must be decided
**per chosen model, empirically** (does tensor even load? what's the real t/s and
max context each way?).

---

## 6. Model fit

_To be filled in after the rubric priorities are locked and coverage gaps are
addressed. No model picks until then._

---

## 7. Open questions

- Set the priority columns in §2 (the key input).
- §3: verify whether `tools` / `chat` actually assert JSON/schema validity, or
  just content — determines if B1 is really covered.
- §4: reweight vs. add-suites — which, and which gap suites are worth building?
- Is OpenWebUI chat knowledge-heavy Q&A (raises B6) or mostly task/tool work
  (lowers B6)? Changes the chat-model bar.

---

## 8. Ideal test suite (in progress)

Built from real tasks, not capability buckets — this is what fixes the relevance
problem in §3 (where `hard-reasoning` discriminates perfectly but measures
nothing we do). Method: **task → what "good" looks like → that becomes the
assertion → source items (public benchmarks + our discriminating survivors) that
match.** Anything that doesn't trace back to a task row here gets cut.

**Cadence:** run only when a **new model releases**, to bench it against the
existing fleet (existing scores are cached → run only the new model, compare).
Because it's infrequent it can be **thorough / expensive** (heavy benchmarks are
fine). Pin the suite version so cross-model comparisons stay apples-to-apples
over time.

**Priority key:** ★ = top stakes · H / M / L. Overall top stakes:
**summarization (B-2), bug-finding (A-2), code review (A-3)**. Chat's #1 is
**clarify (B-3)**, then **structured output (B-6)**. Code *generation* (A-1) is
**low** — Jason prefers writing feature code himself; the AI's coding value is the
**reading-heavy** work (find bugs, review, comprehend, write tests). Rows below
are ordered by priority.

### 8.1 Task inventory — Flow A (coding)

| #   | Task                                              | Pri | "Good" =                  | Failure to catch              |
|-----|---------------------------------------------------|:---:|---------------------------|-------------------------------|
| A-2 | **Bug finding** — fix from description / failing test | ★ | correct root-cause fix  | fixes symptom, not cause      |
| A-3 | **Code review** / PR review                        | ★   | catches real issues       | misses the bug / nitpicks     |
| A-7 | Write a **test suite for a given diff**            | H   | compiles, covers the diff, passes on correct code & fails on a regression | tests that don't compile or don't exercise the change |
| A-4 | Understand a repo (how does X work, summarize)     | M   | accurate, cites real files| confident-but-wrong map       |
| A-5 | Write scripts / configs (yaml, eval, download)     | M   | runnable, idiomatic       | subtle config error           |
| A-6 | Research-while-coding (lib APIs, flags)            | M   | grounded, looks it up     | invents APIs/flags (→ req A5)  |
| A-1 | Implement a feature (greenfield)                  | L   | patch works, tests pass   | _(Jason writes these himself)_ |

### 8.2 Task inventory — Flow B (chat + pipeline)

| #   | Task                                              | Pri | "Good" =                  | Failure to catch              |
|-----|---------------------------------------------------|:---:|---------------------------|-------------------------------|
| B-3 | **Clarify** — *agentic* loop + tools to clean bad OCR / transcripts | ★ chat #1 | iterates / uses tools to fix garbled OCR while preserving meaning | rewrites meaning, or accepts garbled text |
| B-2 | Summarize OCR'd notes                              | ★   | faithful + complete       | drops / invents content       |
| B-6 | Extract structured fields → **JSON** (schema)     | H chat #2 | valid schema, right values | malformed JSON (→ req B1)  |
| B-1 | Interactive technical Q&A (OpenWebUI)             | M   | correct, honest, cites    | hallucinated confidence       |
| B-7 | General brainstorming / planning                  | M   | useful, honest pushback   | sycophancy / wrong facts      |
| B-4 | Classify documents                                | L   | right label               | miscategorizes                |
| B-5 | Contextual enrichment                             | L   | relevant linkage          | spurious context              |

_Add rows for anything missing (prose/docs, SQL, data wrangling, vision beyond
OCR, drafting, …)._

### 8.3 Sourcing (2026 — contamination-aware)

Organizing principle: this suite runs **on each new model release**, so
**contamination is the enemy** — favour sources that are structurally safe:

1. **Time-windowed** public benchmarks — filter to items released *after* the new
   model's training cutoff (LiveCodeBench).
2. **Fresh-2026** benchmarks — too new to be in training corpora yet.
3. **Hand-built on private data** — your repos / notes / OCR aren't in any
   training set → contamination-proof *and* maximally relevant. Strongest
   category here, not a fallback.

**★ tasks**

| Task | 2026 source | Why |
|------|-------------|-----|
| A-2 bug-finding ★ | **LiveCodeBench** (primary) + **Terminal-Bench 2.0** | LiveCodeBench auto-dates problems → filter past the model's cutoff = contamination structurally impossible; includes self-repair (= bug-fixing). Terminal-Bench 2.0 (Jan 2026, 89 CLI/debug tasks) matches bash-heavy loops |
| A-3 code review ★ | hand-built from your repo diffs (reverted/fixed commits) | contamination-proof + your domain; no good public review set |
| B-3 clarify ★ *(uncovered)* | hand-built garbled OCR + gold + cleanup tools | contamination-proof, #1, agentic harness |
| B-2 summarize ★ | hand-built real notes + gold, faithfulness rubric | contamination-proof, your domain |

**Cross-cutting**

| Need | 2026 source | Note |
|------|-------------|------|
| Tool use | **BFCL v4** + our `tools` survivors; MCP-Bench/Universe if pipeline goes MCP | BFCL still standard |
| Structured output (B-6) | **IFEval** + JSON-schema asserts | format compliance → contamination N/A |
| Honesty/grounding (A-6, B-1) | **SimpleQA Verified** (2026) + hand-built "no such flag/API" | **score abstention positively** (reward "I don't know" — your A5) |
| Long-context | **LongBench v2 / Pro** (Jan 2026), *not* needle/RULER; or hand-built "bug across 5 big files" | needle is solved; 2026 hard part is aggregation |
| Test-gen (A-7) | hand-built diff→test (TDD-style); no clean public set | — |

**Drop (stale / saturated in 2026):** Aider polyglot (Dec-2024, maps to low-pri
A-1, 6 toolchains) · TruthfulQA (saturated, bad gold) · original SimpleQA →
Verified · plain needle/RULER → LongBench v2/Pro. SWE-bench Verified still
discriminates for *local* 20–120B models, but its fixed issues are aging into
training sets → secondary only; lean on LiveCodeBench's time-filter.

### 8.4 Harness shape

**We keep promptfoo** — as the orchestrator + scoreboard, not as the runner of
every test. A promptfoo "provider" can be an arbitrary script (our
`agentic/provider.js` already shells out to opencode Docker containers), so the
heavy benchmarks bolt on through that same escape hatch.

```
                  model under test → llm-swap :11436 (OpenAI API)
                                    ▲        ▲        ▲
        ┌───────────────────────────┘        │        └────────────────────────┐
   provider: DIRECT              provider: SHELL→native        provider: SHELL→agent
   prompt → Selene judge         Docker runner                 opencode / user-sim
   • tools (domain)              • LiveCodeBench               • B-3 clarify (agentic)
   • code-review, summarize      • SWE-bench Verified          • tau2 (later)
   • IFEval / SimpleQA / BFCL    • Terminal-Bench 2.0          (already wired today)
        └──────────────────── all return pass/fail ────────────────────┘
                                    ▼
              promptfoo results → compare.sh / summarize.sh
              "run the new model, diff against the cached fleet"
```

- **Native in promptfoo:** prompt→judge tests (domain survivors + ported static
  items: IFEval, SimpleQA, BFCL).
- **Wrapped via shell provider:** execution benchmarks (LiveCodeBench, SWE-bench,
  Terminal-Bench) — run in their own Docker harness; the provider invokes it and
  reads back the score.
- **Already wrapped:** agentic (clarify, τ²) via the opencode provider.

**Decision — keep promptfoo, wrap selectively.** The alternative, **Inspect AI**
(ships many of these prebuilt against an OpenAI endpoint), would mean rebuilding
the domain tests + losing the Selene / compare wiring. Default: keep promptfoo as
hub; **crib reference logic from Inspect's implementations** rather than
reimplement. Migrate only if wrapping proves more painful than that rebuild.
