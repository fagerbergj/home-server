.PHONY: judge-up judge-down swap-up swap-down

judge-up:
	docker compose --profile judge up -d

judge-down:
	docker compose --profile judge down

swap-up:
	docker compose --profile swap up -d --build

swap-down:
	docker compose --profile swap down
