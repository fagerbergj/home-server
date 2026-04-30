# Backups

Backup pipeline for service data and irreplaceable user data. Driven by `scripts/backup.sh`, scheduled via cron.

## Two tiers

| Tier | Where | What | Retention |
|------|-------|------|-----------|
| **Local** | `/mnt/personal/backups/<YYYY-MM-DD>/` (ZFS mirror) | Everything (configs, DB dumps, service data) | 3 most recent dated dirs |
| **Offsite** *(optional)* | `b2:jason-fagerberg:home-server` via restic | Irreplaceable subset only | daily-7, weekly-4, monthly-12 |

Offsite is opt-in — set `RESTIC_REPOSITORY` + `RESTIC_PASSWORD` (and provider creds) in `.env` to enable. If unset, the script just does the local tier.

## What's backed up

| Data | Location | Local | Offsite |
|------|----------|-------|---------|
| Vaultwarden vault | `passwords/data/` | ✓ | ✓ |
| Immich Postgres | `pg_dump` via docker | ✓ | ✓ |
| Immich photos | `/mnt/personal/photos` | (already on ZFS mirror) | ✓ |
| Authentik Postgres | `pg_dump` via docker | ✓ | ✓ |
| Authentik media + certs | `api/data/authentik-{media,certs}` | ✓ | — |
| Documents (reMarkable + vault) | `/mnt/personal/documents` | (already on ZFS mirror) | ✓ |
| rmfakecloud (notes) | `notes/rmfakecloud-data/` | ✓ | ✓ |
| `.env` (encrypted) | `env.gpg` (AES256) | ✓ | ✓ |
| Plex config (excludes Cache) | `plex/config/` | ✓ | — |
| Audiobookshelf config + metadata | `audiobooks/{config,metadata}/` | ✓ | — |
| Sonarr / Radarr / Prowlarr / qBittorrent configs | service dirs | ✓ | — |
| Minecraft world | `minecraft/data/` | ✓ | ✓ |
| Grafana / Prometheus | `monitoring/` | ✓ | — |
| System config | `/etc/fstab`, `/etc/mdadm/mdadm.conf` | ✓ | — |
| Root crontab | `crontab -l` | ✓ | — |

**Not backed up anywhere:**
- Plex/audiobook media files (`/mnt/media/...`) — re-rippable / re-downloadable
- Plex `Cache/` directory — regenerable thumbnails, can be tens of GB
- Docker images / overlay2 — re-pullable from compose
- Ollama models (`/mnt/cache/ollama/`) — `ollama pull` re-downloads

The offsite tier is intentionally narrow: only data where loss would be **emotionally or operationally unrecoverable**. Configs are in git; service state is rebuildable; media is re-rippable.

## Why GPG-encrypt `.env` even on local?

`.env` contains all service credentials, DB passwords, API keys. Local backup lives on `/mnt/personal/backups/` which has standard filesystem perms — adequate but not bulletproof. The GPG layer means if someone gets the backup directory (lost drive, mis-shared snapshot, etc.) the secrets are still encrypted. `BACKUP_GPG_PASSPHRASE` lives in your password manager separately so the on-server `.env` and the off-server `BACKUP_GPG_PASSPHRASE` together reconstruct everything.

## Why restic for offsite?

- **Client-side encryption** — Backblaze (or AWS) never sees plaintext, regardless of bucket-level settings
- **Content-addressed dedup** — daily uploads only transit changed blocks, not the full ~25 GB
- **Provider-agnostic** — change `RESTIC_REPOSITORY` and you switch providers; same script
- **Built-in retention** — `restic forget --prune` does the right thing; no lifecycle policies to author

## Schedule

```bash
sudo crontab -l | grep backup
# 0 3 * * * /home/jason-server/workspace/home-server/scripts/backup.sh >> /var/log/backup.log 2>&1
```

3 AM daily. Local first, then offsite (if configured), then prune.

## Restore

See [setup.md → Restore](setup.md#restore) for the full procedures. Three common scenarios:

1. **One file deleted by accident** — restore from local: `cp /mnt/personal/backups/<date>/<service>/<file> ...`
2. **Service config corrupted** — restore from local: replace the service's `config/` dir with the backup version
3. **Server destroyed (fire / theft / total disk failure)** — bootstrap a fresh server, decrypt env.gpg with `BACKUP_GPG_PASSPHRASE`, run `restic restore` from B2 to rebuild the irreplaceable subset

## Verify it actually works

The dangerous failure mode of any backup system is the silent kind — backup runs daily, succeeds, but the data is corrupted/encrypted-but-unrecoverable/missing-files-you-needed. Quarterly drill:

```bash
# Pick a small file, restore it to /tmp, diff against current
restic restore latest --target /tmp/restore-test --include /mnt/personal/documents/<somefile>
diff /tmp/restore-test/mnt/personal/documents/<somefile> /mnt/personal/documents/<somefile>

# Verify restic repo integrity
restic check                          # quick: just metadata
restic check --read-data-subset 5%    # thorough: actually re-reads 5% of pack files
```

If both pass quarterly, the backup is real. Set a `/schedule` reminder.
