# qBittorrent

Downloads torrents directly to `/mnt/plex01`. Managed via web UI — no desktop needed.

All traffic is routed through Mullvad VPN via [Gluetun](https://github.com/qdm12/gluetun). If the VPN drops, traffic stops — no leaks.

## VPN Setup (one-time)

1. Log in to [mullvad.net](https://mullvad.net) > **Manage Account > WireGuard keys > Generate key**
2. Note the **private key** and the **assigned address** (e.g. `10.x.x.x/32`)
3. Add both values to `~/workspace/home-server/.env` (see root `.env.example`)

To change the exit country, edit `SERVER_COUNTRIES` in `docker-compose.yml`. See the [Mullvad server list](https://mullvad.net/servers) for options.

## Start

```bash
docker compose up -d
```

## Web UI

```
http://<server-ip>:8080
```

Default credentials:
- Username: `admin`
- Password: `adminadmin`

**Change the password immediately** — Tools > Options > Web UI > Authentication.

## Search Engine Plugins

Plugins are in `Search/` and need to be copied into the container's engines directory on first run:

```bash
docker compose up -d
docker cp Search/. qbittorrent:/config/qBittorrent/nova3/engines/
docker restart qbittorrent
```

Plugins included:
- `animetosho.py`
- `audiobookbay.py`
- `kickasstorrents.py`
- `thepiratebay.py`

In the web UI, enable search: View > Search Engine. Search tab will appear.

## Download Paths

Set default save path in Options > Downloads:

| Content | Path |
|---------|------|
| Movies | `/mnt/plex01/movies` |
| TV | `/mnt/plex01/shows` |

## Updating

```bash
docker compose pull
docker compose up -d
```
