# Plex Media Server

## First-Time Setup

1. Check your user's UID/GID match the compose file:
   ```bash
   id $USER
   ```
   Update `PUID` and `PGID` in `docker-compose.yml` if they differ from 1000.

2. Get a claim token from https://www.plex.tv/claim — it expires in 4 minutes, so do this right before starting. Start Plex with the token:
   ```bash# Plex
# One-time claim token to link the server to your plex.tv account.
# Get it from https://plex.tv/claim — expires in 4 minutes.
# Only needed on first start; leave blank after the server is claimed.
# ---------------------------------------------------------------------------
PLEX_CLAIM=claim-xxxxxxxxxxxxxxxxxxxx
   PLEX_CLAIM=claim-xxxxxxxxxxxxxxxxxxxx docker compose up -d
   ```

4. Open a browser on the same local network and go to:
   ```
   http://<server-ip>:32400/web
   ```

5. Walk through the setup wizard — add media libraries pointing to:
   - `/mnt/plex01/movies` — movies
   - `/mnt/plex01/shows` — TV shows

## Enable Hardware Transcoding

Requires Plex Pass.

In Plex Web UI: Settings > Transcoder > check **Use hardware acceleration when available**

To verify it's working, start a stream that forces a transcode and check Settings > Dashboard — you should see `(hw)` next to the session.

## Enable Remote Access

Settings > Remote Access > check **Enable Remote Access**

See the networking setup in [`../setup.md`](../setup.md) for port forwarding and firewall rules.

## Updating

```bash
docker compose pull
docker compose up -d
```

## Logs

```bash
docker compose logs -f plex
```
