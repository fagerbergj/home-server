# qBittorrent

Downloads torrents directly to `/mnt/plex01`. Managed via web UI — no desktop needed.

All traffic is routed through Mullvad VPN via [Gluetun](https://github.com/qdm12/gluetun). If the VPN drops, traffic stops — no leaks.

## Access

```
http://<server-ip>:8080
```

## Download Paths

Set in Options > Downloads:

| Content | Path |
|---------|------|
| Movies | `/mnt/plex01/movies` |
| TV | `/mnt/plex01/shows` |

## Search Engine Plugins

Plugins are in `Search/`. To enable them:

```bash
docker cp Search/. qbittorrent:/config/qBittorrent/nova3/engines/
docker restart qbittorrent
```

In the web UI: View > Search Engine. A Search tab will appear.

Plugins included: `animetosho.py`, `audiobookbay.py`, `kickasstorrents.py`, `thepiratebay.py`

## Changing Exit Country

Edit `SERVER_COUNTRIES` in `docker-compose.yml`. See the [Mullvad server list](https://mullvad.net/servers) for options.

## Updating

```bash
docker compose pull
docker compose up -d
```
