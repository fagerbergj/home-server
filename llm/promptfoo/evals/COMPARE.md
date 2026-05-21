# Blind A/B Comparison

*Last updated: 2026-05-21*

Selene judge picked the best of all 4 models' anonymized responses on each prompt.

## Win rate per suite

| Suite | gpt-oss-120b | llama-3.3-70b | qwen3-coder-next | qwen3.5-9b | qwen3.6-35b |
| --- | --- | --- | --- | --- | --- |
| architecture | 0/10 (0%) | 0/10 (0%) | 6/10 (60%) | 2/10 (20%) | 0/10 (0%) |
| brain-twisters | 4/9 (44%) | 0/9 (0%) | 1/9 (11%) | 2/9 (22%) | 1/9 (11%) |
| calibration | 0/10 (0%) | 0/10 (0%) | 1/10 (10%) | 2/10 (20%) | 3/10 (30%) |
| coding | 4/9 (44%) | 0/9 (0%) | 0/9 (0%) | 0/9 (0%) | 1/9 (11%) |
| hard-reasoning | 0/15 (0%) | 2/15 (13%) | 5/15 (33%) | 5/15 (33%) | 0/15 (0%) |

## Per-test winners

### architecture

- **qwen3-coder-next** — Kotlin: JVM ecosystem and type system
  - _All assertions passed_
- **(no winner)** — Kafka: consumer groups and backpressure
- **(no winner)** — Streaming: operational challenges
- **qwen3.5-9b** — Token storage: localStorage vs httpOnly cookies
  - _All assertions passed_
- **qwen3-coder-next** — Queue vs HTTP: operational costs and failure modes
  - _All assertions passed_
- **qwen3-coder-next** — Queue vs HTTP: coupling and idempotency
  - _All assertions passed_
- **qwen3-coder-next** — Microservices: modular monolith and cost asymmetry
  - _All assertions passed_
- **qwen3.5-9b** — Abstraction: the cost of getting it wrong
  - _All assertions passed_
- **qwen3-coder-next** — CoT: zero-shot vs few-shot, and model size
  - _All assertions passed_
- **qwen3-coder-next** — Prompt chains: latency and interface contracts
  - _All assertions passed_

### brain-twisters

- **gpt-oss-120b** — brain twister: horse race — simplest solution
  - _All assertions passed_
- **gpt-oss-120b** — brain twister: modified Monty Hall — no information revealed
  - _All assertions passed_
- **qwen3.5-9b** — brain twister: Russian roulette — spin or not
  - _All assertions passed_
- **qwen3.6-35b** — brain twister: river crossing with three compartments
  - _All assertions passed_
- **gpt-oss-120b** — brain twister: circle arrangement — who is right of Alan
  - _All assertions passed_
- **gpt-oss-120b** — brain twister: stories above ground
  - _All assertions passed_
- **(no winner)** — brain twister: sentence without Bible words
- **qwen3.5-9b** — brain twister: how many Rs in Strawberry
  - _All assertions passed_
- **qwen3-coder-next** — brain twister: carwash
  - _All assertions passed_

### calibration

- **(no winner)** — Calibration: unknowable internal function
- **qwen3.6-35b** — Calibration: signup metrics for a real-sounding site
  - _All assertions passed_
- **qwen3.5-9b** — Calibration: section of a fake spec document
  - _All assertions passed_
- **qwen3.6-35b** — Calibration: test coverage of a real repo right now
  - _All assertions passed_
- **(no winner)** — Calibration: nonexistent repo
- **qwen3.6-35b** — Calibration: tomorrow's stock close
  - _All assertions passed_
- **qwen3-coder-next** — Calibration: internal database schema
  - _All assertions passed_
- **(no winner)** — Calibration: bug in unseen code
- **qwen3.5-9b** — Calibration: when will my deploy finish
  - _All assertions passed_
- **(no winner)** — Calibration: language-specific best practice in unknown codebase

### coding

- **gpt-oss-120b** — HumanEval/1: separate_paren_groups
  - _All assertions passed_
- **gpt-oss-120b** — HumanEval/4: mean_absolute_deviation
  - _All assertions passed_
- **(no winner)** — HumanEval/5: intersperse
- **qwen3.6-35b** — HumanEval/6: parse_nested_parens depth
  - _All assertions passed_
- **(no winner)** — SQL: debug unexpected query results
- **gpt-oss-120b** — Docker: debug slow builds and security concerns
  - _All assertions passed_
- **gpt-oss-120b** — Go: debug wrong results in concurrent fetch
  - _All assertions passed_
- **(no winner)** — Kotlin: debug NullPointerException in coroutine service
- **(no winner)** — TypeScript: debug silent failures in event processor

### hard-reasoning

- **qwen3.5-9b** — GPQA-style: thermodynamics — adiabatic expansion
  - _All assertions passed_
- **qwen3-coder-next** — GPQA-style: organic chemistry — SN2 stereochemistry
  - _All assertions passed_
- **(no winner)** — GPQA-style: quantum mechanics — particle in a box
- **(no winner)** — GPQA-style: molecular biology — central dogma
- **(no winner)** — GPQA-style: physics — relativistic momentum
- **qwen3-coder-next** — GPQA-style: chemistry — buffer pH calculation
  - _All assertions passed_
- **llama-3.3-70b** — GPQA-style: genetics — Hardy-Weinberg
  - _All assertions passed_
- **llama-3.3-70b** — GPQA-style: physical chemistry — colligative properties
  - _All assertions passed_
- **qwen3.5-9b** — GPQA-style: cell biology — membrane transport
  - _All assertions passed_
- **qwen3-coder-next** — GPQA-style: astronomy — orbital mechanics
  - _All assertions passed_
- **qwen3.5-9b** — ZebraLogic 3x3: three friends, drinks, colors
  - _All assertions passed_
- **qwen3.5-9b** — ZebraLogic 4x4: four houses, four pets, four colors, four hobbies
  - _All assertions passed_
- **qwen3.5-9b** — ZebraLogic 4x4: who came in what order
  - _All assertions passed_
- **qwen3-coder-next** — ZebraLogic 5x5: classic zebra-style
  - _All assertions passed_
- **qwen3-coder-next** — ZebraLogic 4x4: project assignments with constraints
  - _All assertions passed_
