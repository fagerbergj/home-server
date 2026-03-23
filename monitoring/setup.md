# Monitoring — Setup

## Start Netdata

```bash
cd ~/workspace/home-server/monitoring
docker compose up -d
```

## Start Uptime Kuma

```bash
cd ~/workspace/home-server/monitoring
docker compose -f uptime-kuma.yml up -d
```

Then open `http://192.168.50.186:3001` and create your admin account.

### Add Monitors

Add each service as an **HTTP(s)** monitor using the local IP. Do not use external URLs — monitoring should work even when internet is down.

| Name | Type | URL | Port |
|------|------|-----|------|
| Plex | HTTP | `http://192.168.50.186:32400/` | — |
| Immich | HTTP | `http://192.168.50.186:2283/api/server/ping` | — |
| Open WebUI | HTTP | `http://192.168.50.186:3000/` | — |
| Ollama | HTTP | `http://192.168.50.186:11434/` | — |
| qBittorrent | HTTP | `http://192.168.50.186:8080/` | — |
| Jackett | HTTP | `http://192.168.50.186:9117/` | — |
| Audiobookshelf | HTTP | `http://192.168.50.186:13378/` | — |
| Minecraft | TCP Port | `192.168.50.186` | `25565` |

> Do not add a Minecraft monitor if autopause is enabled — mc-monitor pings will prevent the server from pausing.

## Proxy Hosts

Add in Nginx Proxy Manager — see [`networking/setup.md`](../networking/setup.md):

| Service | Domain | Port |
|---------|--------|------|
| Uptime Kuma | `status.jasonfagerberg.duckdns.org` | `3001` |

> Netdata is accessed via Netdata Cloud — no proxy host needed.

## Access

- Uptime Kuma local: `http://192.168.50.186:3001`
- Uptime Kuma remote: `https://status.jasonfagerberg.duckdns.org`
- Netdata: `https://app.netdata.cloud`
