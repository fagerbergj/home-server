# Home Server

Personal home server running Linux Mint. This repo tracks configuration, docker compose files, and setup notes.

## Use Cases

| Service | Purpose |
|---------|---------|
| Plex Media Server | Stream movies/TV locally and remotely |
| Minecraft Server | Self-hosted game server |
| Photo Storage | Personal photo backup and browsing |
| qBittorrent | Download torrents directly to server via web UI |
| Watchtower | Monitors containers and restarts them if they go down |
| Ollama | Local LLM inference (DeepSeek via GPU) |

## OS

**Linux Mint** (Debian-based) — chosen for its familiar desktop environment and stability.

## Architecture

All services run via **Docker Compose**. Each service lives in its own subdirectory with its own `docker-compose.yml`.

```
home-server/
├── plex/
│   └── docker-compose.yml
├── minecraft/
│   └── docker-compose.yml
├── photos/
│   └── docker-compose.yml
├── llm/
│   └── docker-compose.yml
└── README.md
```

## Media Storage

Media drives mounted at `/mnt/<drive-name>/` and referenced as volumes in each service's compose file.

## Hardware

> To be evaluated — see [hardware.md](hardware.md)

## Setup Order

1. OS Install (Linux Mint)
2. NVIDIA drivers
3. Mount drives
4. Docker + NVIDIA Container Toolkit
5. GitHub
6. Networking
7. Services (Plex, Minecraft, Immich, qBittorrent, Ollama + DeepSeek)

See [setup.md](setup.md) for the full step-by-step guide.

## Status

Planning / hardware evaluation phase.
