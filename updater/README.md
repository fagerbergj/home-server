# Watchtower

Automatically pulls and restarts containers when new images are available. Runs daily at 8am UTC (2-3am CT).
Uses the maintained fork [`nickfedor/watchtower`](https://github.com/nicholas-fedor/watchtower), pinned to
major version 1 (the original `containrrr/watchtower` was archived in 2025).

Excluded from auto-update (manual updates required):
- `immich-server`, `immich-machine-learning`, `immich-redis`, `immich-postgres`
- `authentik-server`, `authentik-worker`, `authentik-postgres`, `authentik-redis`
- `quack-postgres`, `langfuse-postgres`, `langfuse-redis`, `langfuse-clickhouse`, `langfuse-minio` (databases and stores)
- `gluetun`, `qbittorrent`, `prowlarr`, `jackett`, `flaresolverr` (shared VPN netns; a gluetun restart cascades)
- `minecraft`, `nginx-proxy-manager`
- `llm-swap-media`, `games` (locally built images)

Sends email notification after each run.

> **Immich and Minecraft** — always check release notes before updating. Breaking changes do occur.

> **Moving to Watchtower v2** drops the legacy `WATCHTOWER_NOTIFICATION_EMAIL_*` settings. Switch to
> `WATCHTOWER_NOTIFICATION_URL` (a Shoutrrr `smtp://` URL) first; store the Gmail app password without
> its spaces, since it goes inside the URL.
