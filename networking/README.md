# Networking

Reverse proxy via Nginx Proxy Manager (NPM). Handles SSL automatically via Let's Encrypt wildcard cert (DNS-01 challenge via DuckDNS). DDNS via a DuckDNS updater container — no router config needed.

## Architecture

```
Internet
    │
    ├── :80 / :443 ──► NPM ──► books.jasonfagerberg.duckdns.org       ──► Audiobookshelf  (13378)
    │                      ──► files.jasonfagerberg.duckdns.org       ──► Nextcloud       (8080)
    │                      ──► llm.jasonfagerberg.duckdns.org         ──► Open WebUI      (3000)
    │                      ──► llm-api.jasonfagerberg.duckdns.org     ──► Ollama API      (11434)
    │                      ──► passwords.jasonfagerberg.duckdns.org   ──► Vaultwarden     (8888)
    │                      ──► photos.jasonfagerberg.duckdns.org      ──► Immich          (2283)
    │                      ──► plex.jasonfagerberg.duckdns.org        ──► Plex            (32400)
    │                      ──► status.jasonfagerberg.duckdns.org      ──► Uptime Kuma     (3001)
    │
    └── :25565 ──────────────────────────────────────────────────► Minecraft    (25565)
```

Minecraft bypasses NPM entirely — raw TCP on port 25565.

## External URLs

| Service | URL |
|---------|-----|
| Audiobookshelf | `https://books.jasonfagerberg.duckdns.org` |
| Immich | `https://photos.jasonfagerberg.duckdns.org` |
| Minecraft | `jasonfagerberg.duckdns.org:25565` |
| Nextcloud | `https://files.jasonfagerberg.duckdns.org` |
| Ollama API | `https://llm-api.jasonfagerberg.duckdns.org` |
| Open WebUI | `https://llm.jasonfagerberg.duckdns.org` |
| Plex | `https://plex.jasonfagerberg.duckdns.org` |
| Uptime Kuma | `https://status.jasonfagerberg.duckdns.org` |
| Vaultwarden | `https://passwords.jasonfagerberg.duckdns.org` |

## Internal Only

| Service | URL |
|---------|-----|
| AdGuard Home | `http://192.168.50.186:3003` |

## NPM Admin

```
http://<server-local-ip>:81
```
