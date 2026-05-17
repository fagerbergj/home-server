.PHONY: judge-up judge-down swap-up swap-down

judge-up:
	docker compose --profile judge up -d llm-judge

judge-down:
	docker compose --profile judge stop llm-judge

swap-up:
	docker compose --profile swap up -d --build llm-swap

swap-down:
	docker compose --profile swap stop llm-swap
