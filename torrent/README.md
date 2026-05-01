# Torrent Stack

Automated media pipeline: Sonarr/Radarr find and request content → qBittorrent downloads it through AirVPN → files land in the right Plex folder, renamed correctly.

All torrent traffic is routed through AirVPN via [Gluetun](https://github.com/qdm12/gluetun). If the VPN drops, traffic stops — no leaks. AirVPN supports static port forwarding, which is required for healthy seeding and inbound peer connections.

## Access

| Service | URL | Purpose |
|---------|-----|---------|
| qBittorrent | `http://192.168.50.186:8080` | Download client |
| Prowlarr | `http://192.168.50.186:9696` | Indexer manager (syncs to Sonarr/Radarr) |
| Sonarr | `http://192.168.50.186:8989` | TV show library manager |
| Radarr | `http://192.168.50.186:7878` | Movie library manager |

## Download Paths

qBittorrent's default save path is `/mnt/media/downloads/`. Sonarr and Radarr override this per-category and move completed files to their final locations automatically.

| Content | Staging | Final |
|---------|---------|-------|
| Movies | `/mnt/media/downloads/` | `/mnt/media/movies` |
| TV | `/mnt/media/downloads/` | `/mnt/media/shows` |

## Search Engine Plugins

Plugins are in `search/`. To enable them:

```bash
docker cp search/. qbittorrent:/config/torrent/nova3/engines/
docker restart qbittorrent
```

In the web UI: View > Search Engine. A Search tab will appear.

Plugins included: `animetosho.py`, `audiobookbay.py`, `kickasstorrents.py`, `solidtorrents.py`, `thepiratebay.py`

## Prowlarr

Prowlarr manages indexers and syncs them automatically to Sonarr and Radarr. All indexer traffic routes through the VPN via Gluetun.

```
http://192.168.50.186:9696
```

## Changing Exit Country

Edit `SERVER_COUNTRIES` in `docker-compose.yml`. See the [AirVPN server list](https://airvpn.org/status/) for options. Note that the WireGuard config and reserved port are tied to the key/account, not a specific server, so changing the country doesn't require regenerating anything.

## Configarr (TRaSH-Guides sync)

[Configarr](https://github.com/raydak-labs/configarr) keeps Sonarr/Radarr quality profiles and custom formats in sync with TRaSH-Guides. Config lives in `configarr/config/config.yml` (templates: all English profiles + anime for both).

```bash
docker compose run --rm configarr
```

Runs once and exits. Re-run to pick up upstream changes.

## Updating

```bash
docker compose pull
docker compose up -d
```
