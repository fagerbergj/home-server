# Monitoring

- **Grafana** — dashboard UI for all metrics. Web UI at port 3004.
- **Prometheus** — metrics collection and storage (30-day retention).
- **Node Exporter** — host metrics: CPU, RAM, disk, network, temperatures.
- **cAdvisor** — per-container CPU and RAM metrics.
- **NVIDIA GPU Exporter** — GPU utilization, VRAM, temperature.
- **smartctl Exporter** — drive S.M.A.R.T. health (reallocated sectors, pending sectors, temps).
- **Uptime Kuma** — service status page showing each container up/down.

## Access

| Tool | URL |
|------|-----|
| Grafana (local) | `http://192.168.50.186:3004` |
| Grafana (remote) | `https://dashboard.jasonfagerberg.duckdns.org` |
| Uptime Kuma (local) | `http://192.168.50.186:3001` |
| Uptime Kuma (remote) | `https://status.jasonfagerberg.duckdns.org` |

## Updating

```bash
cd ~/workspace/home-server/monitoring
docker compose pull && docker compose up -d
```
