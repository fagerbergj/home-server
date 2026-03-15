# Watchtower

Monitors running containers and restarts them if they go down. Does **not** pull new images — updates are manual.

## Manual Updates

```bash
cd ~/workspace/home-server/<service>
docker compose pull
docker compose up -d
```

> **Immich and Minecraft** — always check release notes before updating. Breaking changes do occur.
