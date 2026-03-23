# Watchtower + Diun — Setup

Start this last, after all other services are up:

```bash
cd ~/workspace/home-server/updater
docker compose up -d
```

## Verify

```bash
docker compose logs watchtower
docker compose logs diun
```

Watchtower should show `Using notifications: smtp` and its next scheduled run.
Diun should show `Starting Diun` and its next scheduled run.
