# Immich — Photo Storage

Self-hosted Google Photos alternative. Runs four containers: server, ML worker, Postgres, Redis.

## First-Time Setup

1. Generate the env file:
   ```bash
   ./generate-env.sh
   ```

2. Create the photo upload directory on the storage drive:
   ```bash
   sudo mkdir -p /mnt/personal01/photos
   sudo chown immich:personal-rw /mnt/personal01/photos
   ```

3. Start all services:
   ```bash
   docker compose up -d
   ```

4. Check everything came up:
   ```bash
   docker compose ps
   ```

5. Open the web UI:
   ```
   http://<server-ip>:2283
   ```

6. Create your admin account on first visit.

## Uploading Photos

- **Web UI** — drag and drop in the browser
- **Mobile app** — Immich has iOS and Android apps with automatic background backup

## GPU Acceleration (ML)

The machine learning container uses the GTX 1070 Ti for face detection and image classification. This runs automatically — no extra config needed after nvidia-container-toolkit is installed.

GPU is only used during indexing (initial library scan and new photo processing), not during normal browsing.

## Updating

Immich updates frequently. Always check the release notes before updating as breaking changes do occur.

```bash
docker compose pull
docker compose up -d
```

## Logs

```bash
docker compose logs -f immich-server
docker compose logs -f immich-machine-learning
```

## Data Locations

Both photos and the Postgres database live on the RAID array — if the OS drive fails, your data survives:

| Data | Location |
|------|----------|
| Photos | `/mnt/personal01/photos` |
| Database | `/mnt/personal01/db` |

## Backups

The RAID protects against single drive failure but not accidental deletion or both drives failing. To dump the database manually:

```bash
docker exec immich-postgres pg_dumpall -U immich > immich-db-backup-$(date +%F).sql
```
