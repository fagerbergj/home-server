# Home Server

Personal home server running Ubuntu Server 24.04 LTS. This repo tracks configuration, docker compose files, and setup notes.

## Use Cases

| Service | Purpose |
|---------|---------|
| AdGuard Home | Network-wide DNS ad blocker |
| Audiobookshelf | Self-hosted audiobook server |
| faster-whisper | GPU-accelerated speech-to-text for audio transcription |
| CouchDB | reMarkable notes backup (local vault) |
| Diun | Watches excluded images and emails when updates are available |
| Grafana + Prometheus | System and container metrics dashboard |
| Immich | Personal photo backup and browsing with ML-powered search |
| Minecraft Server | Self-hosted game server |
| llm-swap + Open WebUI | Local LLM inference via GPU (llama.cpp behind an OpenAI-compatible router) |
| Plex Media Server | Stream movies/TV locally and remotely |
| qBittorrent | Download torrents directly to server via web UI |
| document-pipeline | Ingests reMarkable notes + uploaded files: OCR, summarize, classify, embed |
| rmfakecloud | Self-hosted reMarkable cloud — syncs tablet notes |
| Tailscale | Mesh VPN — remote access to LAN-only admin UIs, exit node, MagicDNS |
| Uptime Kuma | Service status page — shows each container up/down |
| Vaultwarden | Self-hosted Bitwarden-compatible password manager |
| Watchtower | Auto-updates containers daily, emails on update |

## OS

**Ubuntu Server 24.04 LTS** — chosen for strong GPU driver support (ROCm for AMD) and Docker compatibility.

## Architecture

All services run via **Docker Compose**. Each service lives in its own subdirectory with its own `docker-compose.yml`.

```
home-server/
├── networking/       # Nginx Proxy Manager + DuckDNS updater
├── plex/             # Plex Media Server
├── minecraft/        # Minecraft NeoForge server
├── photos/           # Immich photo storage
├── llm/              # llm-swap (llama.cpp) + Open WebUI
├── torrent/          # qBittorrent behind Mullvad VPN
├── audiobooks/       # Audiobookshelf
├── updater/          # Watchtower (auto-updates) + Diun (update notifications)
├── monitoring/       # Grafana + Prometheus + Uptime Kuma
├── passwords/        # Vaultwarden password manager
├── adblock/          # AdGuard Home DNS ad blocker
├── notes/            # rmfakecloud + OCR bridge + Open WebUI knowledge base
├── audio/            # faster-whisper GPU transcription
└── README.md
```

## Media Storage

Media drives mounted at `/mnt/<drive-name>/` and referenced as volumes in each service's compose file.

## Hardware

> To be evaluated — see [hardware.md](hardware.md)

## Setup Order

1. OS Install + [Router & Firewall](networking/setup.md) (DHCP reservation, port forwarding, ufw)
2. GitHub (clone repo, create .env)
3. AMD GPU Drivers (ROCm)
4. Mount Drives + Alerts
5. Docker
6. [Nginx Proxy Manager](networking/setup.md) (proxy hosts, SSL)
7. [Tailscale](networking/setup.md) (mesh VPN for tailnet-only admin UIs)
8. Services — see each service's `setup.md`

See [setup.md](setup.md) for the full step-by-step guide.

## Status

Active — all services running.
