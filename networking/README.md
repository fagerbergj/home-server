# Networking

Reverse proxy via Nginx Proxy Manager (NPM). Handles SSL automatically via Let's Encrypt. DDNS via ASUS router built-in client — no extra software needed.

## Architecture

```
Internet
    │
    ├── :80 / :443 ──► NPM ──► plex.jasonfagerberg.asuscomm.com        ──► Plex       (32400)
    │                      ──► photos.jasonfagerberg.asuscomm.com      ──► Immich     (2283)
    │                      ──► llm.jasonfagerberg.asuscomm.com         ──► Open WebUI (3000)
    │                      ──► llm-api.jasonfagerberg.asuscomm.com     ──► Ollama API (11434)
    │
    └── :25565 ──────────────────────────────────────────────────► Minecraft    (25565)
```

Minecraft bypasses NPM entirely — raw TCP on port 25565.

## External URLs

| Service | URL |
|---------|-----|
| Plex | `https://plex.jasonfagerberg.asuscomm.com` |
| Immich | `https://photos.jasonfagerberg.asuscomm.com` |
| Open WebUI | `https://llm.jasonfagerberg.asuscomm.com` |
| Ollama API | `https://llm-api.jasonfagerberg.asuscomm.com` |
| Minecraft | `jasonfagerberg.asuscomm.com:25565` |

## NPM Admin

```
http://<server-local-ip>:81
```
