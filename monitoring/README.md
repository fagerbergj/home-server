# Monitoring

- **Grafana** — dashboard UI for all metrics. Web UI at port 3004.
- **Prometheus** — metrics collection and storage (30-day retention).
- **Node Exporter** — host metrics: CPU, RAM, disk, network, temperatures.
- **cAdvisor** — per-container CPU and RAM metrics.
- **NVIDIA GPU Exporter** — GPU utilization, VRAM, temperature.
- **smartctl Exporter** — drive S.M.A.R.T. health (reallocated sectors, pending sectors, temps).
- **Uptime Kuma** — service status page showing each container up/down.

## Access

Tailnet-only — see [../networking/setup.md](../networking/setup.md) Phase 7.

| Tool | URL |
|------|-----|
| Grafana | `http://jason-server:3004` |
| Uptime Kuma | `http://jason-server:3001` |

## Updating

```bash
cd ~/workspace/home-server/monitoring
docker compose pull && docker compose up -d
```
