# Torrent Stack

Automated media pipeline: Sonarr/Radarr find and request content → qBittorrent downloads it through AirVPN → files land in the right Plex folder, renamed correctly.

All torrent traffic is routed through AirVPN via [Gluetun](https://github.com/qdm12/gluetun). If the VPN drops, traffic stops — no leaks. AirVPN supports static port forwarding, which is required for healthy seeding and inbound peer connections.

Dependents (qBittorrent, Sonarr-feeders, etc.) gate on Gluetun's healthcheck and auto-restart when Gluetun restarts (`depends_on.restart: true`), so watchtower-triggered Gluetun updates no longer leave qBittorrent stuck in `firewalled` with a stale namespace.

A `tailscale-vpn-exit` sidecar piggy-backs on Gluetun's namespace to expose AirVPN as an additional Tailscale exit node — useful for routing phone or laptop traffic through AirVPN on demand. Optional, off by default. See [../networking/setup.md](../networking/setup.md) Phase 7.

## Access

Tailnet-only — see [../networking/setup.md](../networking/setup.md) Phase 7.

| Service | URL | Purpose |
|---------|-----|---------|
| qBittorrent | `http://jason-server:8080` | Download client |
| Prowlarr | `http://jason-server:9696` | Indexer manager (syncs to Sonarr/Radarr) |
| Jackett | `http://jason-server:9117` | Manual indexer search for backfilling old content |
| Sonarr | `http://jason-server:8989` | TV show library manager |
| Radarr | `http://jason-server:7878` | Movie library manager |

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
http://jason-server:9696
```

## Jackett

Jackett is kept alongside Prowlarr for **manual backfilling of older content**. Sonarr/Radarr (via Prowlarr) handle newer and ongoing releases well, but for hunting down legacy stuff the Jackett UI is more practical for hand-searching across trackers.

```
http://jason-server:9117
```

Also routed through Gluetun.

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
