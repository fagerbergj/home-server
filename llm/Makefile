.PHONY: swap-up swap-down media-up

# jaison
swap-up:
	docker compose --profile swap up -d --build llm-swap

swap-down:
	docker compose --profile swap stop llm-swap

# jason-server: qdrant + open-webui (llm-swap lives on jaison)
media-up:
	docker compose --profile media up -d
