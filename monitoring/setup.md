# Monitoring — Setup

## Start

```bash
cd ~/workspace/home-server/monitoring
docker compose up -d
```

## Grafana

Web UI at `http://192.168.50.186:3004`. Default login: `admin` / `admin` — change on first login.

Dashboards (Node Exporter Full, cAdvisor) are provisioned automatically. If datasource template variables aren't replaced on first run:

```bash
sed -i 's/${DS_PROMETHEUS}/Prometheus/g' ~/workspace/home-server/monitoring/grafana-dashboards/node-exporter.json
sed -i 's/${DS_PROMETHEUS}/Prometheus/g' ~/workspace/home-server/monitoring/grafana-dashboards/cadvisor.json
docker compose restart grafana
```

## Glances

Web UI available at `http://192.168.50.186:61208`. Start/stop as needed — only uses significant CPU while the page is open.

```bash
docker compose stop glances   # when done
docker compose start glances  # when needed
```

> Do not expose Glances externally — no auth. Use SSH tunnel for remote access:
> ```bash
> ssh -L 61208:localhost:61208 jason-server
> ```

## Uptime Kuma

Open `http://192.168.50.186:3001` and create your admin account.

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

> Do not add a Minecraft monitor if autopause is enabled — pings will prevent the server from pausing.

## Proxy Hosts

Add in Nginx Proxy Manager — see [`networking/setup.md`](../networking/setup.md):

| Service | Domain | Port |
|---------|--------|------|
| Uptime Kuma | `status.jasonfagerberg.duckdns.org` | `3001` |

## Access

- Glances: `http://192.168.50.186:61208`
- Uptime Kuma local: `http://192.168.50.186:3001`
- Uptime Kuma remote: `https://status.jasonfagerberg.duckdns.org`
