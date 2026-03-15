# qBittorrent — Setup

## 1. Generate a Mullvad WireGuard key

1. Log in to [mullvad.net](https://mullvad.net) > **Manage Account > WireGuard keys > Generate key**
2. Note the **private key** and the **assigned address** (e.g. `10.x.x.x/32`)
3. Add both to `~/workspace/home-server/.env` (see root `.env.example`)

## 2. Start services

```bash
docker compose up -d
```

## 3. Change the default password

Open `http://<server-ip>:8080` and log in with `admin` / `adminadmin`.

Go to Tools > Options > Web UI > Authentication and set a strong password.

## 4. Copy search plugins

```bash
docker cp Search/. qbittorrent:/config/qBittorrent/nova3/engines/
docker restart qbittorrent
```

## 5. Set download paths

In Options > Downloads, set the default save path and per-category paths:

| Content | Path |
|---------|------|
| Movies | `/mnt/plex01/movies` |
| TV | `/mnt/plex01/shows` |

## Verify

1. Open `http://<server-ip>:8080` and confirm you can log in with your new password
2. Check the VPN is connected — the Gluetun container logs should show a successful WireGuard handshake:
   ```bash
   docker compose logs gluetun | grep -i "connected\|handshake"
   ```
3. Add a test torrent and confirm it downloads to `/mnt/plex01/`
