# Monitoring

**Uptime Kuma** — service status page showing each container up/down. Accessible at `https://status.jasonfagerberg.duckdns.org`.

## Access

| URL | |
|-----|--|
| Local | `http://192.168.50.186:3001` |
| Remote | `https://status.jasonfagerberg.duckdns.org` |

## Updating

```bash
cd ~/workspace/home-server/monitoring
docker compose pull && docker compose up -d
```
