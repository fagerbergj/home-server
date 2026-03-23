# Home Server

Personal home server running Ubuntu Server 24.04 LTS. This repo tracks configuration, docker compose files, and setup notes.

## Use Cases

| Service | Purpose |
|---------|---------|
| Plex Media Server | Stream movies/TV locally and remotely |
| Minecraft Server | Self-hosted game server |
| Immich | Personal photo backup and browsing with ML-powered search |
| qBittorrent | Download torrents directly to server via web UI |
| Audiobookshelf | Self-hosted audiobook server |
| Watchtower | Monitors containers and restarts them if they go down |
| Netdata | Real-time server and Docker container monitoring (via Netdata Cloud) |
| Uptime Kuma | Service status page — shows each container up/down |
| Ollama + Open WebUI | Local LLM inference via GPU |

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
├── qbittorrent/      # qBittorrent behind Mullvad VPN
├── audiobooks/       # Audiobookshelf
├── watchtower/       # Container auto-restart
├── monitoring/       # Netdata + Uptime Kuma
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
