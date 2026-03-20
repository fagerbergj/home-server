# Networking

Reverse proxy via Nginx Proxy Manager (NPM). Handles SSL automatically via Let's Encrypt wildcard cert (DNS-01 challenge via DuckDNS). DDNS via a DuckDNS updater container — no router config needed.

## Architecture

```
Internet
    │
    ├── :80 / :443 ──► NPM ──► plex.jasonfagerberg.duckdns.org        ──► Plex       (32400)
    │                      ──► photos.jasonfagerberg.duckdns.org      ──► Immich     (2283)
    │                      ──► llm.jasonfagerberg.duckdns.org         ──► Open WebUI (3000)
    │                      ──► llm-api.jasonfagerberg.duckdns.org     ──► Ollama API (11434)
    │                      ──► books.jasonfagerberg.duckdns.org      ──► Audiobookshelf (13378)
    │
    └── :25565 ──────────────────────────────────────────────────► Minecraft    (25565)
```

Minecraft bypasses NPM entirely — raw TCP on port 25565.

## External URLs

| Service | URL |
|---------|-----|
| Plex | `https://plex.jasonfagerberg.duckdns.org` |
| Immich | `https://photos.jasonfagerberg.duckdns.org` |
| Open WebUI | `https://llm.jasonfagerberg.duckdns.org` |
| Ollama API | `https://llm-api.jasonfagerberg.duckdns.org` |
| Audiobookshelf | `https://books.jasonfagerberg.duckdns.org` |
| Minecraft | `jasonfagerberg.duckdns.org:25565` |

## NPM Admin

```
http://<server-local-ip>:81
```
