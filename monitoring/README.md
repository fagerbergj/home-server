# Monitoring

- **Glances** — real-time system metrics, Docker container stats. Web UI at port 61208.
- **Uptime Kuma** — service status page showing each container up/down.

## Access

| Tool | URL |
|------|-----|
| Glances (local) | `http://192.168.50.186:61208` |
| Uptime Kuma (local) | `http://192.168.50.186:3001` |
| Uptime Kuma (remote) | `https://status.jasonfagerberg.duckdns.org` |

## Updating

```bash
cd ~/workspace/home-server/monitoring
docker compose pull && docker compose up -d
```
