# Plex Media Server

Runs via Docker using the [linuxserver/plex](https://hub.docker.com/r/linuxserver/plex) image. Media lives on the `media` ZFS pool at `/mnt/media`, mounted read-only via the `plex-ro` group.

## Access

```
http://192.168.50.186:32400/web
```

## Library Paths

| Library | Path |
|---------|------|
| Movies | `/mnt/media/movies` |
| TV Shows | `/mnt/media/shows` |
| Audiobooks | `/mnt/media/audiobooks` |

## Hardware Transcoding

Requires Plex Pass.

Settings > Transcoder > check **Use hardware acceleration when available**

To verify: start a stream that forces a transcode and check Settings > Dashboard — you should see `(hw)` next to the session.

## Remote Access

Settings > Remote Access > check **Enable Remote Access**

Port forwarding and firewall rules are handled in [networking/setup.md](../networking/setup.md).

## Updating

```bash
docker compose pull
docker compose up -d
```

## Logs

```bash
docker compose logs -f plex
```
