# Blind A/B Comparison

*Last updated: 2026-05-20*

Selene judge picked the best of all 4 models' anonymized responses on each prompt.

## Win rate per suite

| Suite | llama-3.3-70b | qwen3-coder-next | qwen3.5-9b | qwen3.6-35b |
| --- | --- | --- | --- | --- |
| architecture | 0/10 (0%) | 6/10 (60%) | 2/10 (20%) | 1/10 (10%) |
| brain-twisters | 1/9 (11%) | 3/9 (33%) | 4/9 (44%) | 0/9 (0%) |
| calibration | 0/10 (0%) | 0/10 (0%) | 6/10 (60%) | 0/10 (0%) |
| hard-reasoning | 2/15 (13%) | 5/15 (33%) | 5/15 (33%) | 0/15 (0%) |

## Per-test winners

### architecture

- **qwen3-coder-next** — Kotlin: JVM ecosystem and type system
  - _All assertions passed_
- **qwen3.5-9b** — Kafka: consumer groups and backpressure
  - _All assertions passed_
- **(no winner)** — Streaming: operational challenges
- **qwen3.5-9b** — Token storage: localStorage vs httpOnly cookies
  - _All assertions passed_
- **qwen3-coder-next** — Queue vs HTTP: operational costs and failure modes
  - _All assertions passed_
- **qwen3-coder-next** — Queue vs HTTP: coupling and idempotency
  - _All assertions passed_
- **qwen3-coder-next** — Microservices: modular monolith and cost asymmetry
  - _All assertions passed_
- **qwen3-coder-next** — Abstraction: the cost of getting it wrong
  - _All assertions passed_
- **qwen3-coder-next** — CoT: zero-shot vs few-shot, and model size
  - _All assertions passed_
- **qwen3.6-35b** — Prompt chains: latency and interface contracts
  - _All assertions passed_

### brain-twisters

- **qwen3-coder-next** — brain twister: horse race — simplest solution
  - _All assertions passed_
- **qwen3.5-9b** — brain twister: modified Monty Hall — no information revealed
  - _All assertions passed_
- **qwen3-coder-next** — brain twister: Russian roulette — spin or not
  - _All assertions passed_
- **qwen3-coder-next** — brain twister: river crossing with three compartments
  - _All assertions passed_
- **qwen3.5-9b** — brain twister: circle arrangement — who is right of Alan
  - _All assertions passed_
- **(no winner)** — brain twister: stories above ground
- **llama-3.3-70b** — brain twister: sentence without Bible words
  - _All assertions passed_
- **qwen3.5-9b** — brain twister: how many Rs in Strawberry
  - _All assertions passed_
- **qwen3.5-9b** — brain twister: carwash
  - _All assertions passed_

### calibration

- **(no winner)** — Calibration: unknowable internal function
- **qwen3.5-9b** — Calibration: signup metrics for a real-sounding site
  - _All assertions passed_
- **qwen3.5-9b** — Calibration: section of a fake spec document
  - _All assertions passed_
- **qwen3.5-9b** — Calibration: test coverage of a real repo right now
  - _All assertions passed_
- **(no winner)** — Calibration: nonexistent repo
- **qwen3.5-9b** — Calibration: tomorrow's stock close
  - _All assertions passed_
- **qwen3.5-9b** — Calibration: internal database schema
  - _All assertions passed_
- **(no winner)** — Calibration: bug in unseen code
- **qwen3.5-9b** — Calibration: when will my deploy finish
  - _All assertions passed_
- **(no winner)** — Calibration: language-specific best practice in unknown codebase

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
