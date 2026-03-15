# Plex Media Server

Runs via Docker using the [linuxserver/plex](https://hub.docker.com/r/linuxserver/plex) image. Media lives on `/mnt/plex01` (and optionally `/mnt/plex02`), mounted as read-only volumes.

## Access

```
http://<server-ip>:32400/web
```

## Library Paths

| Library | Path |
|---------|------|
| Movies | `/mnt/plex01/movies` |
| TV Shows | `/mnt/plex01/shows` |
| plex02 Movies | `/mnt/plex02/movies` (if present) |
| plex02 TV Shows | `/mnt/plex02/shows` (if present) |

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
