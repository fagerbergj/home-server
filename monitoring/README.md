# Monitoring

Two monitoring tools:

- **Netdata** — real-time system metrics, Docker container stats, alerts. Accessed via Netdata Cloud.
- **Uptime Kuma** — service status page showing each container up/down. Accessible at `https://status.jasonfagerberg.duckdns.org`.

## Access

| Tool | URL |
|------|-----|
| Netdata Cloud | `https://app.netdata.cloud` |
| Uptime Kuma (local) | `http://192.168.50.186:3001` |
| Uptime Kuma (remote) | `https://status.jasonfagerberg.duckdns.org` |

## Compose Files

| File | Service |
|------|---------|
| `docker-compose.yml` | Netdata |
| `uptime-kuma.yml` | Uptime Kuma |

## Updating

```bash
cd ~/workspace/home-server/monitoring
docker compose pull && docker compose up -d
docker compose -f uptime-kuma.yml pull && docker compose -f uptime-kuma.yml up -d
```
