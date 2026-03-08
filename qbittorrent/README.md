# qBittorrent

Downloads torrents directly to `/mnt/plex01`. Managed via web UI — no desktop needed.

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
| TV | `/mnt/plex01/tv` |

## Adding to NPM

Add a proxy host in Nginx Proxy Manager to access qBittorrent remotely:
- Domain: `torrent.yourname.asuscomm.com`
- Forward port: `8080`
- Enable SSL

## Updating

```bash
docker compose pull
docker compose up -d
```
