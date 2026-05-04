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

## Access

Grafana and Uptime Kuma are tailnet-only — see [`networking/setup.md`](../networking/setup.md) Phase 7.

- Grafana: `http://jason-server:3004`
- Uptime Kuma: `http://jason-server:3001`
