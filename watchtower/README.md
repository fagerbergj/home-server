# Watchtower

Monitors running containers and restarts them if they go down. Does **not** pull new images — updates are done manually.

## Start

```bash
docker compose up -d
```

## Manual Updates

To update a specific service when you're ready:

```bash
cd ~/workspace/home-server/<service>
docker compose pull
docker compose up -d
```

> **Immich and Minecraft** — always check release notes before updating. Breaking changes do occur.
