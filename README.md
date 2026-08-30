# Home Server

Personal home server running Ubuntu Server 26.04 LTS. This repo tracks configuration, docker compose files, and setup notes.

## Use Cases

| Service | Purpose |
|---------|---------|
| AdGuard Home | Network-wide DNS ad blocker |
| Audiobookshelf | Self-hosted audiobook server |
| CouchDB | reMarkable notes backup (local vault) |
| Diun | Watches excluded images and emails when updates are available |
| Games | Next.js games launcher (Kings Corner and future browser games) |
| Grafana + Prometheus | System and container metrics dashboard |
| Immich | Personal photo backup and browsing with ML-powered search |
| Langfuse | LLM observability + eval datasets, fed by quack's OTLP traces |
| llm-swap + Open WebUI | Local LLM inference via GPU (llama.cpp behind an OpenAI-compatible router) |
| Plex Media Server | Stream movies/TV locally and remotely |
| qBittorrent | Download torrents directly to server via web UI |
| quack | GitHub PR-review bot — clones repos and posts inline reviews on `@quack` / PR-open |
| rmfakecloud | Self-hosted reMarkable cloud — syncs tablet notes |
| Tailscale | Mesh VPN — remote access to LAN-only admin UIs, exit node, MagicDNS |
| Uptime Kuma | Service status page — shows each container up/down |
| Vaultwarden | Self-hosted Bitwarden-compatible password manager |
| Watchtower | Auto-updates containers daily, emails on update |

## OS

**Ubuntu Server 26.04 LTS** — current kernel for the hardware, NVIDIA driver in the archive, and Docker compatibility.

## Architecture

All services run via **Docker Compose**. Each service lives in its own subdirectory with its own `docker-compose.yml`.

```
home-server/
├── networking/       # Nginx Proxy Manager + DuckDNS updater
├── plex/             # Plex Media Server
├── games/            # Next.js games launcher (Kings Corner)
├── photos/           # Immich photo storage
├── llm/              # llm-swap (llama.cpp) + Open WebUI
├── torrent/          # qBittorrent behind Mullvad VPN
├── audiobooks/       # Audiobookshelf
├── updater/          # Watchtower (auto-updates) + Diun (update notifications)
├── monitoring/       # Grafana + Prometheus + Uptime Kuma
├── passwords/        # Vaultwarden password manager
├── adblock/          # AdGuard Home DNS ad blocker
├── notes/            # rmfakecloud (reMarkable cloud emulator)
├── langfuse/         # Langfuse (LLM observability + evals)
├── quack/            # GitHub PR-review bot (built from ~/workspace/agent-researcher)
└── README.md
```

## Media Storage

Media drives mounted at `/mnt/<drive-name>/` and referenced as volumes in each service's compose file.

## Hardware

> To be evaluated — see [hardware.md](hardware.md)

## Setup Order

1. OS Install + [Router & Firewall](networking/setup.md) (DHCP reservation, port forwarding, ufw)
2. GitHub (clone repo, create .env)
3. NVIDIA GPU Driver
4. Mount Drives + Alerts
5. Docker
6. [Nginx Proxy Manager](networking/setup.md) (proxy hosts, SSL)
7. [Tailscale](networking/setup.md) (mesh VPN for tailnet-only admin UIs)
8. Services — see each service's `setup.md`

See [setup.md](setup.md) for the full step-by-step guide.

## Status

Active — all services running.
