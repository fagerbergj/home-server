# Hermes Agent

[Hermes Agent](https://github.com/NousResearch/hermes-agent) (Nous Research) on the
media box, driven by the local `qwen3.8-27b` through llm-swap. A trial: a general
assistant for home-server and network questions, with quack staying the code reviewer.

## Access

From the media box:

```bash
docker exec -it hermes hermes          # interactive chat
docker exec -it hermes hermes doctor   # check the config and the model connection
```

No messaging gateway (Telegram, Discord, …) is configured yet; `hermes gateway setup`
inside the container adds one.

## Model

`jaison/qwen3.8-27b` via `llm-swap-media` on `127.0.0.1:11436` — the same model and
router quack uses, so Hermes sessions share the 27B's six vLLM slots with prod.

## Safety

- Commands run inside this container as uid 1000: no host shell, no Docker socket.
- The repo is mounted read-only from a separate clone (`~/workspace/home-server-view`)
  that holds tracked files only, so no service `.env` secrets reach the agent.
- `approvals.mode: manual`: every command Hermes flags as dangerous waits for a yes.
- The container uses the host network, so the agent can reach the internet. See
  Hermes' [egress isolation](https://hermes-agent.nousresearch.com/docs/user-guide/egress/network-isolation)
  guide before giving it credentials or broader access.

## Setup

```bash
git clone ~/workspace/home-server ~/workspace/home-server-view
mkdir -p data && cp config.yaml.example data/config.yaml
docker compose up -d
docker exec -it hermes hermes doctor
```

Refresh the repo view after pushing changes: `git -C ~/workspace/home-server-view pull`.

## Updating

Bump the image tag in `docker-compose.yml` (pinned to a release) and `docker compose up -d`.
