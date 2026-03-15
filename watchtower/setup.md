# Watchtower — Setup

Start this last, after all other services are up:

```bash
docker compose up -d
```

## Verify

```bash
docker compose ps
```

Watchtower should show as `Up`. To confirm it can see other containers:

```bash
docker logs watchtower
```

You should see it listing the running containers it's now monitoring.
