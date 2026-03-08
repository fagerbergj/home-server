# Networking

Reverse proxy via Nginx Proxy Manager (NPM). Handles SSL automatically via Let's Encrypt.

## Architecture

```
Internet
    │
    ├── :80 / :443 ──► NPM ──► plex.yourdomain.com    ──► Plex      (32400)
    │                      ──► photos.yourdomain.com  ──► Immich     (2283)
    │
    └── :25565 ────────────────────────────────────────► Minecraft   (25565)
```

## Prerequisites

- ASUS DDNS set up (free, built into your RT-AX58U)
- In router UI: WAN > DDNS > enable, choose a hostname e.g. `yourname.asuscomm.com`
- The router will automatically update DNS if your home IP changes

Your services will be accessible at:
```
plex.yourname.asuscomm.com
photos.yourname.asuscomm.com
```

> You can swap to a custom domain later by updating NPM and DNS records — takes ~10 minutes.

## Router Port Forwarding

Forward these ports to the server's local IP:

| External Port | Internal Port | Protocol | Service |
|---------------|---------------|----------|---------|
| 80 | 80 | TCP | NPM (HTTP / SSL verification) |
| 443 | 443 | TCP | NPM (HTTPS) |
| 25565 | 25565 | TCP | Minecraft |

## Firewall (ufw)

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 25565/tcp
sudo ufw enable
```

## Start NPM

```bash
docker compose up -d
```

## NPM First-Time Setup

1. Open the admin UI: `http://<server-local-ip>:81`
2. Default login:
   - Email: `admin@example.com`
   - Password: `changeme`
3. Change your email and password immediately

## Add Proxy Hosts

For each service, go to **Proxy Hosts > Add Proxy Host**:

### Plex
- Domain: `plex.yourdomain.com`
- Scheme: `http`
- Forward Hostname/IP: `127.0.0.1`
- Forward Port: `32400`
- Enable **Websockets Support**
- SSL tab: request a Let's Encrypt cert, enable **Force SSL**

### Immich
- Domain: `photos.yourdomain.com`
- Scheme: `http`
- Forward Hostname/IP: `127.0.0.1`
- Forward Port: `2283`
- Enable **Websockets Support**
- SSL tab: request a Let's Encrypt cert, enable **Force SSL**

## Mobile Photo Uploads (Immich)

Install the Immich app on your phone (iOS or Android). In the app settings:
- Server URL: `https://photos.yourdomain.com`
- Log in with your Immich account
- Enable **Automatic Background Backup**

Photos will upload automatically over both WiFi and mobile data.

## Minecraft

Minecraft bypasses NPM entirely — it uses raw TCP on port 25565. Friends connect using:
```
yourdomain.com:25565
```
or just your home IP if you don't want to use a subdomain.

## Dynamic DNS

Handled automatically by your ASUS RT-AX58U via the built-in DDNS feature. No extra software needed.
