# Plex — Setup

Migrating from an existing Plex install on your main PC.

## 1. Stop and remove Plex on your main PC

```bash
sudo systemctl stop plexmediaserver
sudo systemctl disable plexmediaserver
sudo apt remove plexmediaserver
```

## 2. Copy Plex data to the server

Run this from your main PC once the server is up and SSH is working:

```bash
sudo rsync -av --progress \
  /var/lib/plexmediaserver/Library/ \
  jason@<server-ip>:~/workspace/home-server/plex/config/Library/
```

## 3. Start Plex

No claim token needed — the server is already linked to your account via the migrated data:

```bash
docker compose up -d
```

Open `http://<server-ip>:32400/web` and verify your libraries and watch history are intact.

## 4. Update library paths

Your old library paths won't match the new server. In the Plex Web UI, update each library:

Settings > Libraries > (select library) > Edit > Manage Locations — remove the old path and add the new one.

- Movies → `/mnt/plex01/movies`
- TV Shows → `/mnt/plex01/shows`
- plex02 Movies → `/mnt/plex02/movies` (if present)
- plex02 TV Shows → `/mnt/plex02/shows` (if present)

Watch history and metadata will be preserved.
