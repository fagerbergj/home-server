# Networking

Reverse proxy via Nginx Proxy Manager (NPM). Handles SSL automatically via Let's Encrypt wildcard cert (DNS-01 challenge via DuckDNS). DDNS via a DuckDNS updater container — no router config needed.

## Architecture

```
Internet
    │
    ├── :80 / :443 ──► NPM ──► api.jasonfagerberg.duckdns.org          ──► Traefik        (8090)
    │                      ──► auth.jasonfagerberg.duckdns.org        ──► Traefik        (8090) ──► Authentik (9000)
    │                      ──► books.jasonfagerberg.duckdns.org       ──► Audiobookshelf  (13378)
    │                      ──► llm.jasonfagerberg.duckdns.org         ──► Open WebUI      (3000)
    │                      ──► llm-api.jasonfagerberg.duckdns.org     ──► Ollama API      (11434)
    │                      ──► passwords.jasonfagerberg.duckdns.org   ──► Vaultwarden     (8888)
    │                      ──► photos.jasonfagerberg.duckdns.org      ──► Immich          (2283)
    │                      ──► plex.jasonfagerberg.duckdns.org        ──► Plex            (32400)
    │                      ──► remarkable.jasonfagerberg.duckdns.org  ──► rmfakecloud     (3005)
    │                      ──► status.jasonfagerberg.duckdns.org      ──► Uptime Kuma     (3001)
    │
    └── :25565 ──────────────────────────────────────────────────► Minecraft    (25565)
```

Minecraft bypasses NPM entirely — raw TCP on port 25565.

## External URLs

| Service | URL |
|---------|-----|
| API Gateway | `https://api.jasonfagerberg.duckdns.org` |
| API Docs | `https://api.jasonfagerberg.duckdns.org/docs` |
| Authentik | `https://auth.jasonfagerberg.duckdns.org` |
| Audiobookshelf | `https://books.jasonfagerberg.duckdns.org` |

| Minecraft | `jasonfagerberg.duckdns.org:25565` |
| Open WebUI | `https://llm.jasonfagerberg.duckdns.org` |
| Ollama API | `https://llm-api.jasonfagerberg.duckdns.org` |
| Vaultwarden | `https://passwords.jasonfagerberg.duckdns.org` |
| Immich | `https://photos.jasonfagerberg.duckdns.org` |
| Plex | `https://plex.jasonfagerberg.duckdns.org` |
| rmfakecloud | `https://remarkable.jasonfagerberg.duckdns.org` |
| Uptime Kuma | `https://status.jasonfagerberg.duckdns.org` |

## Internal Only

| Service | URL |
|---------|-----|
| AdGuard Home | `http://192.168.50.186:3003` |

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
