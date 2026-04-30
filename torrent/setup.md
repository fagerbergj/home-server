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
docker cp search/. qbittorrent:/config/qBittorrent/nova3/engines/
docker restart qbittorrent
```

## 5. Configure Prowlarr

1. Open `http://192.168.50.186:9696` and set an admin password
2. **Add indexers:** Indexers > Add Indexer — add whatever public indexers you want (1337x, YTS, EZTV, etc.)
3. **FlareSolverr** (needed for Cloudflare-protected indexers): Settings > Indexers > Add FlareSolverr proxy, URL: `http://127.0.0.1:8191`
4. **Connect to Sonarr/Radarr:** Settings > Apps > + — add both Sonarr and Radarr so Prowlarr syncs indexers to them automatically
   - Sonarr: `http://192.168.32.1:8989`, API key from Sonarr Settings > General
   - Radarr: `http://192.168.32.1:7878`, API key from Radarr Settings > General
   - Note: use `192.168.32.1` (Docker host gateway), not the LAN IP — Prowlarr runs on Gluetun's network and can't reach the host directly via `192.168.50.186`

## 6. Set download paths

In Options > Downloads, set the default save path and per-category paths:

| Content | Path |
|---------|------|
| Movies | `/mnt/media/movies` |
| TV | `/mnt/media/shows` |

## 7. Configure Sonarr (TV shows)

Open `http://192.168.50.186:8989`.

**Download client:**
Settings > Download Clients > + > qBittorrent
- Host: `192.168.50.186`
- Port: `8080`
- Username/password: your qBittorrent credentials
- Category: `sonarr`
- Test and save.

**Root folders:**
Settings > Media Management > Root Folders > + `/mnt/media/shows`

Note: indexers are synced automatically from Prowlarr — no need to add them manually here.

---

## 8. Configure Radarr (movies)

Open `http://192.168.50.186:7878`. Same steps as Sonarr:

**Download client:** same settings, category: `radarr`

**Root folders:** `/mnt/media/movies`

Note: indexers are synced automatically from Prowlarr.

---

## 9. Update qBittorrent download path

In qBittorrent: Options > Downloads > Default Save Path → `/mnt/media/downloads/`

Sonarr and Radarr override this per-category automatically, so existing categories (`movies`, `tv`) don't need manual changes — Sonarr/Radarr will reconfigure them on first use.

---

## 10. Configure Configarr (TRaSH-Guides sync)

Configarr pushes TRaSH-Guides quality profiles and custom formats into Sonarr and Radarr. Templates enabled in `configarr/config/config.yml`: all English profiles (WEB-1080p, WEB-2160p for TV; HD Bluray+WEB, UHD Bluray+WEB, Remux+WEB 1080p/2160p for movies) plus anime for both.

1. Copy the secrets file and fill in API keys (Sonarr/Radarr Settings > General):
   ```bash
   cp configarr/config/secrets.yml.example configarr/config/secrets.yml
   $EDITOR configarr/config/secrets.yml
   ```
2. Run it (one-shot — runs, syncs, exits):
   ```bash
   docker compose run --rm configarr
   ```
3. Re-run any time to resync against upstream TRaSH/recyclarr changes.

---

## Verify

1. Open `http://192.168.50.186:8080` and confirm you can log in with your new password
2. Check the VPN is connected — the Gluetun container logs should show a successful WireGuard handshake:
   ```bash
   docker compose logs gluetun | grep -i "connected\|handshake"
   ```
3. In Sonarr: add a TV show and confirm a torrent appears in qBittorrent
4. In Radarr: add a movie and confirm a torrent appears in qBittorrent
5. After a download completes, confirm Sonarr/Radarr move it to the correct folder with proper naming
