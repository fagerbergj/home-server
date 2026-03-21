# Monitoring — Setup

## Start Netdata

```bash
cd ~/workspace/home-server/monitoring
docker compose up -d
```

## Proxy Host

Add in Nginx Proxy Manager — see [`networking/setup.md`](../networking/setup.md):

| Service | Domain | Port |
|---------|--------|------|
| Netdata | `monitoring.jasonfagerberg.duckdns.org` | `19999` |

## Access

- Local: `http://192.168.50.186:19999`
- Remote: `https://monitoring.jasonfagerberg.duckdns.org`
