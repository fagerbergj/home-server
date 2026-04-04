# Torrent Stack

Automated media pipeline: Sonarr/Radarr find and request content → qBittorrent downloads it through Mullvad VPN → files land in the right Plex folder, renamed correctly.

All torrent traffic is routed through Mullvad VPN via [Gluetun](https://github.com/qdm12/gluetun). If the VPN drops, traffic stops — no leaks.

## Access

| Service | URL | Purpose |
|---------|-----|---------|
| qBittorrent | `http://192.168.50.186:8080` | Download client |
| Jackett | `http://192.168.50.186:9117` | Indexer proxy |
| Sonarr | `http://192.168.50.186:8989` | TV show library manager |
| Radarr | `http://192.168.50.186:7878` | Movie library manager |

## Download Paths

qBittorrent's default save path is `/mnt/plex01/downloads/`. Sonarr and Radarr override this per-category and move completed files to their final locations automatically.

| Content | Staging | Final |
|---------|---------|-------|
| Movies | `/mnt/plex01/downloads/` | `/mnt/plex01/movies` (or `/mnt/plex02/movies`) |
| TV | `/mnt/plex01/downloads/` | `/mnt/plex01/shows` (or `/mnt/plex02/shows`) |

## Search Engine Plugins

Plugins are in `search/`. To enable them:

```bash
docker cp search/. qbittorrent:/config/torrent/nova3/engines/
docker restart qbittorrent
```

In the web UI: View > Search Engine. A Search tab will appear.

Plugins included: `animetosho.py`, `audiobookbay.py`, `kickasstorrents.py`, `solidtorrents.py`, `thepiratebay.py`

## Jackett

Jackett runs alongside qBittorrent and gluetun, routing through the VPN. It proxies searches across many torrent indexers.

```
http://192.168.50.186:9117
```

Config file for the qBittorrent plugin: `config/torrent/nova3/engines/jackett.json`

To write the config (file is owned by the container user):

```bash
echo '{"api_key":"YOUR_API_KEY_HERE","url":"http://127.0.0.1:9117","tracker_first":false,"thread_count":20}' | sudo tee config/torrent/nova3/engines/jackett.json
```

## Changing Exit Country

Edit `SERVER_COUNTRIES` in `docker-compose.yml`. See the [Mullvad server list](https://mullvad.net/servers) for options.

## Updating

```bash
docker compose pull
docker compose up -d
```
