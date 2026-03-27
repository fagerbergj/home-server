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

Open `http://192.168.50.186:8080` and log in with `admin` / `adminadmin`.

Go to Tools > Options > Web UI > Authentication and set a strong password.

## 4. Copy search plugins

```bash
docker cp search/. qbittorrent:/config/torrent/nova3/engines/
docker restart qbittorrent
```

## 5. Configure Jackett

1. Open `http://192.168.50.186:9117` and set an admin password (wrench icon)
2. Copy the API key from the top-right corner
3. Create the plugin config file (the file may be owned by the container user, so use `tee`):

```bash
echo '{"api_key":"YOUR_API_KEY_HERE","url":"http://127.0.0.1:9117","tracker_first":false,"thread_count":20}' | sudo tee ~/workspace/home-server/torrent/config/torrent/nova3/engines/jackett.json
```

4. In qBittorrent, install the Jackett search plugin:
   - Go to the Search tab > **Search plugins…** > **Install a new one** > **Web link**
   - Paste: `https://raw.githubusercontent.com/torrent/search-plugins/master/nova3/engines/jackett.py`

## 6. Set download paths

In Options > Downloads, set the default save path and per-category paths:

| Content | Path |
|---------|------|
| Movies | `/mnt/plex01/movies` |
| TV | `/mnt/plex01/shows` |

## Verify

1. Open `http://192.168.50.186:8080` and confirm you can log in with your new password
2. Check the VPN is connected — the Gluetun container logs should show a successful WireGuard handshake:
   ```bash
   docker compose logs gluetun | grep -i "connected\|handshake"
   ```
3. Add a test torrent and confirm it downloads to `/mnt/plex01/`
