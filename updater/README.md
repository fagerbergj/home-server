# Watchtower

Automatically pulls and restarts containers when new images are available. Runs daily at 4am CT.

Excluded from auto-update (manual updates required):
- `immich-server`, `immich-machine-learning`, `immich-redis`, `immich-postgres`
- `minecraft`
- `remarkable-bridge`, `nginx-proxy-manager`, `faster-whisper` (locally built images)

Sends email notification after each run.

> **Immich and Minecraft** — always check release notes before updating. Breaking changes do occur.
