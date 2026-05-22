# Blind A/B Comparison

*Last updated: 2026-05-22*

Selene judge picked the best of all 4 models' anonymized responses on each prompt.

## Win rate per suite

| Suite | gpt-oss-120b | qwen3-coder-next | qwen3.5-9b | qwen3.6-35b |
| --- | --- | --- | --- | --- |
| architecture | 0/10 (0%) | 1/10 (10%) | 0/10 (0%) | 0/10 (0%) |
| brain-twisters | 2/9 (22%) | 0/9 (0%) | 2/9 (22%) | 1/9 (11%) |
| calibration | 4/10 (40%) | 1/10 (10%) | 1/10 (10%) | 4/10 (40%) |
| coding | 3/9 (33%) | 0/9 (0%) | 0/9 (0%) | 0/9 (0%) |

## Per-test winners

<details><summary>architecture</summary>

| Test | Winner |
| --- | --- |
| Kotlin: JVM ecosystem and type system | (no winner) |
| Kafka: consumer groups and backpressure | (no winner) |
| Streaming: operational challenges | (no winner) |
| Token storage: localStorage vs httpOnly cookies | (no winner) |
| Queue vs HTTP: operational costs and failure modes | (no winner) |
| Queue vs HTTP: coupling and idempotency | (no winner) |
| Microservices: modular monolith and cost asymmetry | (no winner) |
| Abstraction: the cost of getting it wrong | (no winner) |
| CoT: zero-shot vs few-shot, and model size | qwen3-coder-next |
| Prompt chains: latency and interface contracts | (no winner) |

</details>

<details><summary>brain-twisters</summary>

| Test | Winner |
| --- | --- |
| brain twister: horse race — simplest solution | (no winner) |
| brain twister: modified Monty Hall — no information revealed | (no winner) |
| brain twister: Russian roulette — spin or not | (no winner) |
| brain twister: river crossing with three compartments | qwen3.5-9b |
| brain twister: circle arrangement — who is right of Alan | gpt-oss-120b |
| brain twister: stories above ground | gpt-oss-120b |
| brain twister: sentence without Bible words | qwen3.6-35b |
| brain twister: how many Rs in Strawberry | qwen3.5-9b |
| brain twister: carwash | (no winner) |

</details>

<details><summary>calibration</summary>

| Test | Winner |
| --- | --- |
| Calibration: unknowable internal function | qwen3.6-35b |
| Calibration: signup metrics for a real-sounding site | qwen3.6-35b |
| Calibration: section of a fake spec document | qwen3.6-35b |
| Calibration: test coverage of a real repo right now | gpt-oss-120b |
| Calibration: nonexistent repo | qwen3.6-35b |
| Calibration: tomorrow's stock close | qwen3.5-9b |
| Calibration: internal database schema | qwen3-coder-next |
| Calibration: bug in unseen code | gpt-oss-120b |
| Calibration: when will my deploy finish | gpt-oss-120b |
| Calibration: language-specific best practice in unknown codebase | gpt-oss-120b |

</details>

<details><summary>coding</summary>

| Test | Winner |
| --- | --- |
| HumanEval/1: separate_paren_groups | gpt-oss-120b |
| HumanEval/4: mean_absolute_deviation | gpt-oss-120b |
| HumanEval/5: intersperse | (no winner) |
| HumanEval/6: parse_nested_parens depth | gpt-oss-120b |
| SQL: debug unexpected query results | (no winner) |
| Docker: debug slow builds and security concerns | (no winner) |
| Go: debug wrong results in concurrent fetch | (no winner) |
| Kotlin: debug NullPointerException in coroutine service | (no winner) |
| TypeScript: debug silent failures in event processor | (no winner) |

</details>
