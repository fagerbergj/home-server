# Immich — Photo Storage

Self-hosted Google Photos alternative. Runs four containers: server, ML worker, Postgres, Redis.

## Access

```
http://192.168.50.186:2283
```

External: `https://photos.jasonfagerberg.duckdns.org`

## Uploading Photos

- **Web UI** — drag and drop in the browser
- **Mobile app** — Immich has iOS and Android apps with automatic background backup
  - Server URL: `https://photos.jasonfagerberg.duckdns.org`
  - Enable **Automatic Background Backup**

## GPU Acceleration (ML)

The machine learning container uses the RTX 3090 for face detection and image classification. This runs automatically — no extra config needed after nvidia-container-toolkit is installed.

GPU is only used during indexing (initial library scan and new photo processing), not during normal browsing.

## Data Locations

| Data | Location | Notes |
|------|----------|-------|
| Photos | `/mnt/personal/photos` | ZFS mirror — protected against single drive failure, snapshotted by `zfs-auto-snapshot` |
| Database | `photos/postgres/` | On OS NVMe — fast, acceptable to lose (rebuilds from photos) |

## Backups

To dump the database manually:

```bash
docker exec immich-postgres pg_dumpall -U immich > immich-db-backup-$(date +%F).sql
```

## Updating

Always check the [release notes](https://github.com/immich-app/immich/releases) before updating — breaking changes do occur.

```bash
docker compose pull
docker compose up -d
```

## Logs

```bash
docker compose logs -f immich-server
docker compose logs -f immich-machine-learning
```
