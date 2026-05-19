# Eval Results

*Last updated: 2026-05-19*

| Model | architecture | coding | brain-twisters |
| --- | --- | --- | --- |
| llama-3.3-70b | ✅ 28/32 (88%) 19t/s | ⚠️ 8/12 (67%) 17t/s | ⚠️ 7/9 (78%) 18t/s |
| qwen3-coder-next | ✅ 27/32 (84%) 48t/s | ✅ 10/12 (83%) 44t/s | ⚠️ 6/9 (67%) 47t/s |
| qwen3.5-9b | ⚠️ 20/32 (62%) | ⚠️ 9/12 (75%) | ✅ 8/9 (89%) |
| qwen3.6-35b | ✅ 30/32 (94%) | ❌ 7/12 (58%) | ⚠️ 6/9 (67%) |

**Thresholds:** ✅ ≥80%  ⚠️ 60–79%  ❌ <60% or errors

**tok/s:** median decode speed across all tests in that suite

**Suites:** architecture (32) · coding (12) · function-call (11) · brain-twisters (9) · math (9) · tools (14)
