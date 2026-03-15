# Plex Media Server

## Migrating from an Existing Plex Install

### 1. Stop and remove Plex on your main PC

```bash
sudo systemctl stop plexmediaserver
sudo systemctl disable plexmediaserver
sudo apt remove plexmediaserver
```

### 2. Copy Plex data to the server

Run this from your main PC once the server is up and SSH is working:

```bash
sudo rsync -av --progress \
  /var/lib/plexmediaserver/Library/ \
  jason@<server-ip>:~/workspace/home-server/plex/config/Library/
```

### 3. Start Plex on the server

No claim token needed — the server is already linked to your account via the migrated data:

```bash
docker compose up -d
```

Open `http://<server-ip>:32400/web` and verify your libraries and watch history are intact.

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
