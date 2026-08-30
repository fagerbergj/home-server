.PHONY: swap-up swap-down media-up

# jaison
swap-up:
	docker compose --profile swap up -d --build llm-swap

swap-down:
	docker compose --profile swap stop llm-swap

# jason-server: llm-swap-media (3090: embed + 9B, peers to jaison) + qdrant + open-webui
media-up:
	docker compose --profile media up -d --build
