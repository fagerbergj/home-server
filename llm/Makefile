.PHONY: judge-up judge-down swap-up swap-down

judge-up:
	docker compose --profile judge up -d llama-judge

judge-down:
	docker compose --profile judge stop llama-judge

swap-up:
	docker compose --profile swap up -d --build llama-swap

swap-down:
	docker compose --profile swap stop llama-swap
