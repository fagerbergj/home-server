# Watchtower + Diun

## Watchtower

Automatically pulls and restarts containers when new images are available. Runs daily at 4am CT.

Excluded from auto-update (manual updates required):
- `immich-server`, `immich-machine-learning`, `immich-redis`, `immich-postgres`
- `minecraft`

Sends email notification after each run.

> **Immich and Minecraft** — always check release notes before updating. Breaking changes do occur.

## Diun

Watches all container images and sends a weekly email when new versions are available. Runs every Monday at 4am CT. Does not update anything — notification only.

Useful for knowing when excluded containers (Immich, Minecraft) have updates ready.
