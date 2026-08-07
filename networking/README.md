# Networking

Two ingress paths:

- **Public** — Nginx Proxy Manager (NPM) terminates TLS for services that need to be reachable from non-tailnet devices (the reMarkable tablet, family Plex clients, mobile apps with no Tailscale, etc.). Wildcard Let's Encrypt cert via DuckDNS DNS-01 challenge. DDNS via the DuckDNS updater container.
- **Tailnet** — Tailscale gives every enrolled device a `100.x.x.x` IP and a MagicDNS hostname. Admin UIs and personal-only services live here, never on the public internet.

## Architecture

```
Internet
    │
    ├── :80 / :443 ──► NPM ──► api.jasonfagerberg.duckdns.org          ──► Traefik        (8090)
    │                      ──► auth.jasonfagerberg.duckdns.org        ──► Traefik        (8090) ──► Authentik (9000)
    │                      ──► books.jasonfagerberg.duckdns.org       ──► Audiobookshelf  (13378)
    │                      ──► games.jasonfagerberg.duckdns.org       ──► Games           (3006)
    │                      ──► llm.jasonfagerberg.duckdns.org         ──► Open WebUI      (3000)
    │                      ──► passwords.jasonfagerberg.duckdns.org   ──► Vaultwarden     (8888)
    │                      ──► photos.jasonfagerberg.duckdns.org      ──► Immich          (2283)
    │                      ──► plex.jasonfagerberg.duckdns.org        ──► Plex            (32400)
    │                      ──► quack.jasonfagerberg.duckdns.org       ──► Traefik        (8090) ──► quack (webhook public / UI via Authentik)
    │                      ──► remarkable.jasonfagerberg.duckdns.org  ──► rmfakecloud     (3005)
    │
    └── :25565 ──────────────────────────────────────────────────► Minecraft      (25565)

Tailnet (100.64.0.0/10)
    │
    └── tailscale ──► jason-server ──► :81    NPM admin
                                  ──► :8091  Traefik dashboard
                                  ──► :3003  AdGuard Home
                                  ──► :3004  Grafana
                                  ──► :3001  Uptime Kuma
                                  ──► :8080  qBittorrent
                                  ──► :8989  Sonarr
                                  ──► :7878  Radarr
                                  ──► :9000  Authentik (break-glass)
                                  ──► :3006  Games
                                  ──► :3007  deepwiki
                                  ──► :11436 llm-swap API
                                  ──► 192.168.50.0/24 (subnet route — full LAN access)
```

Minecraft bypasses NPM entirely — raw TCP on port 25565.

## Public URLs

Reachable from anywhere on the internet via NPM.

| Service | URL |
|---------|-----|
| API Gateway | `https://api.jasonfagerberg.duckdns.org` |
| API Docs | `https://api.jasonfagerberg.duckdns.org/docs` |
| Authentik | `https://auth.jasonfagerberg.duckdns.org` |
| Audiobookshelf | `https://books.jasonfagerberg.duckdns.org` |
| Games | `https://games.jasonfagerberg.duckdns.org` |
| Open WebUI | `https://llm.jasonfagerberg.duckdns.org` |
| Vaultwarden | `https://passwords.jasonfagerberg.duckdns.org` |
| Immich | `https://photos.jasonfagerberg.duckdns.org` |
| Plex | `https://plex.jasonfagerberg.duckdns.org` |
| quack | `https://quack.jasonfagerberg.duckdns.org` (UI via Authentik; `…/api/v1/github/webhook` public for the GitHub App) |
| rmfakecloud | `https://remarkable.jasonfagerberg.duckdns.org` |

## Tailnet URLs

Reachable only from devices enrolled in the tailnet. MagicDNS resolves `jason-server` to its `100.x.x.x` IP automatically. Subnet route also makes `192.168.50.186:<port>` work from anywhere.

| Service | URL |
|---------|-----|
| NPM admin | `http://jason-server:81` |
| Traefik dashboard | `http://jason-server:8091/dashboard/` |
| AdGuard Home | `http://jason-server:3003` |
| Grafana | `http://jason-server:3004` |
| Uptime Kuma | `http://jason-server:3001` |
| qBittorrent | `http://jason-server:8080` |
| Sonarr | `http://jason-server:8989` |
| Radarr | `http://jason-server:7878` |
| Authentik (break-glass) | `http://jason-server:9000` |
| Games | `http://jason-server:3006` |
| deepwiki | `http://jason-server:3007` |
| llm-swap API | `http://jason-server:11436/v1` |

## NPM Admin

```
http://<server-local-ip>:81
```

## Updating

NPM is a locally built image (adds `certbot-dns-duckdns`) so Watchtower skips it. To update manually:

```bash
docker pull jc21/nginx-proxy-manager:latest
docker compose -f networking/docker-compose.yml build --no-cache && docker compose -f networking/docker-compose.yml up -d
```
