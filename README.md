# Home Server

Personal home server running Ubuntu Server 24.04 LTS. This repo tracks configuration, docker compose files, and setup notes.

## Use Cases

| Service | Purpose |
|---------|---------|
| AdGuard Home | Network-wide DNS ad blocker |
| Audiobookshelf | Self-hosted audiobook server |
| CouchDB (LiveSync) | Self-hosted Obsidian sync backend |
| Diun | Watches excluded images and emails when updates are available |
| Grafana + Prometheus | System and container metrics dashboard |
| Immich | Personal photo backup and browsing with ML-powered search |
| Minecraft Server | Self-hosted game server |
| Ollama + Open WebUI | Local LLM inference via GPU |
| Plex Media Server | Stream movies/TV locally and remotely |
| qBittorrent | Download torrents directly to server via web UI |
| remarkable-bridge | Queues note images and OCRs them nightly via Ollama |
| rmfakecloud | Self-hosted reMarkable cloud — syncs tablet notes |
| Uptime Kuma | Service status page — shows each container up/down |
| Vaultwarden | Self-hosted Bitwarden-compatible password manager |
| Watchtower | Auto-updates containers daily, emails on update |

## OS

**Ubuntu Server 24.04 LTS** — chosen for strong NVIDIA/CUDA driver support and Docker compatibility.

## Architecture

All services run via **Docker Compose**. Each service lives in its own subdirectory with its own `docker-compose.yml`.

```
home-server/
├── networking/       # Nginx Proxy Manager + DuckDNS updater
├── plex/             # Plex Media Server
├── minecraft/        # Minecraft NeoForge server
├── photos/           # Immich photo storage
├── llm/              # Ollama + Open WebUI
├── torrent/          # qBittorrent behind Mullvad VPN
├── audiobooks/       # Audiobookshelf
├── updater/          # Watchtower (auto-updates) + Diun (update notifications)
├── monitoring/       # Grafana + Prometheus + Uptime Kuma
├── passwords/        # Vaultwarden password manager
├── adblock/          # AdGuard Home DNS ad blocker
├── notes/            # rmfakecloud + OCR bridge + CouchDB (Obsidian sync)
└── README.md
```

## Media Storage

Media drives mounted at `/mnt/<drive-name>/` and referenced as volumes in each service's compose file.

## Hardware

> To be evaluated — see [hardware.md](hardware.md)

## Setup Order

1. OS Install + [Router & Firewall](networking/setup.md) (DHCP reservation, port forwarding, ufw)
2. GitHub (clone repo, create .env)
3. NVIDIA Drivers
4. Mount Drives + Alerts
5. Docker + NVIDIA Container Toolkit
6. [Nginx Proxy Manager](networking/setup.md) (proxy hosts, SSL)
7. Services — see each service's `setup.md`

See [setup.md](setup.md) for the full step-by-step guide.

## Status

Active — all services running.
