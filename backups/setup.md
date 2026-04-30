# Backups — Setup

End-to-end setup for both tiers. Local runs out-of-the-box once `BACKUP_GPG_PASSPHRASE` is set; offsite needs ~10 minutes of B2 console + env work.

## Prerequisites

- `/mnt/personal` mounted (ZFS pool from phase4)
- `.env` exists at the repo root
- Docker running (Immich + Authentik Postgres containers up so `pg_dump` works)

## 1. Local backup — minimum viable

### a. Generate `BACKUP_GPG_PASSPHRASE`

The script GPG-encrypts `.env` into `env.gpg` in each daily backup. Without this, the `.env` step is skipped and you lose the ability to restore credentials in disaster recovery.

```bash
echo "BACKUP_GPG_PASSPHRASE: $(openssl rand -base64 48)"
```

Copy the output value. Save it to **two places**:

1. Your password manager (Bitwarden / 1Password / etc.) under an entry like "Home server — backup GPG passphrase"
2. The server's `.env`:

```bash
cd ~/workspace/home-server
echo 'export BACKUP_GPG_PASSPHRASE=<paste-the-value-here>' >> .env
```

If you ever need to decrypt `env.gpg` during recovery, you'll get the passphrase from the password manager — it cannot be recovered from the server itself.

### b. Run a test backup

```bash
sudo ./scripts/backup.sh
ls -lh /mnt/personal/backups/$(date +%Y-%m-%d)/
```

Should see directories for vaultwarden, plex-config, sonarr-config, etc., plus `immich-postgres.dump`, `authentik-postgres.dump`, `env.gpg`, and `system/`.

### c. Schedule via cron

```bash
sudo crontab -e
# Add:
0 3 * * * /home/jason-server/workspace/home-server/scripts/backup.sh >> /var/log/backup.log 2>&1
```

3 AM daily — early enough to finish before morning, late enough to be after backup-bait events like overnight Sonarr imports.

```bash
sudo touch /var/log/backup.log
sudo chmod 644 /var/log/backup.log
```

Verify:

```bash
sudo crontab -l | grep backup
# Tomorrow morning:
tail /var/log/backup.log
```

## 2. Offsite backup — Backblaze B2 + restic

Optional but strongly recommended. ~$1.80/year for ~25 GB of irreplaceable data, instant restores, no lifecycle complexity.

### a. Create the B2 bucket

1. **Sign up** at [backblaze.com/cloud-storage](https://www.backblaze.com/cloud-storage.html) (no credit card needed for first 10 GB; payment for more)
2. **Buckets** → **Create a Bucket**
   - Name: `jason-fagerberg` (must be globally unique on B2; pick something with your handle)
   - Files in Bucket: **Private**
   - Default Encryption: **Enable** (server-side, B2-managed keys — defense in depth)
   - Object Lock: optional. Enable governance mode + 30-day retention for ransomware protection (tradeoff: `restic forget --prune` won't free data still under lock)
3. **App Keys** → **Add a New Application Key**
   - Name: `home-server-restic`
   - Allow access to: **A specific bucket: jason-fagerberg**
   - Type of access: **Read and Write**
   - Click **Create New Key**
   - **Immediately copy `keyID` and `applicationKey`** — the key disappears once you close the dialog. If you miss it, delete and recreate.

### b. Generate `RESTIC_PASSWORD`

Restic's encryption key. Lose it → backups are unrecoverable.

```bash
echo "RESTIC_PASSWORD: $(openssl rand -base64 48)"
```

Save to **the same two places** as `BACKUP_GPG_PASSPHRASE`:
1. Password manager
2. Server's `.env`

### c. Wire env vars

Append to `.env`:

```bash
export RESTIC_REPOSITORY=b2:jason-fagerberg:home-server
export RESTIC_PASSWORD=<paste-generated-passphrase>
export B2_ACCOUNT_ID=<keyID-from-B2>
export B2_ACCOUNT_KEY=<applicationKey-from-B2>
```

The `home-server` after the bucket name is just a path-within-bucket — lets you reuse the same bucket for other restic repos later (`b2:jason-fagerberg:laptop`, etc.).

### d. Install restic and bootstrap the repo

```bash
sudo apt install -y restic

# Source the new env vars into your shell
source ~/workspace/home-server/.env

# Initialize the remote repo (one-time)
restic init
# Should print: "created restic repository <id> at b2:jason-fagerberg:home-server"
```

If `restic init` errors with "already initialized" — that's fine, repo already exists.
If it errors with auth failure — `B2_ACCOUNT_ID` / `B2_ACCOUNT_KEY` is wrong; regenerate the application key in B2.

### e. Run a test backup

```bash
sudo ./scripts/backup.sh
```

Look for the offsite section in output:

```
[03:01:23] Offsite backup (restic → b2:jason-fagerberg:home-server)...
[03:01:55]   Restic backup ok. Pruning snapshots (keep daily-7, weekly-4, monthly-12)...
[03:01:58]   Latest offsite snapshot:
ID        Time                 Host        Tags
abc123    2026-04-30 03:01:24  jason-server automated, 2026-04-30
```

First run uploads the full ~25 GB and takes 5–30 minutes depending on upstream bandwidth. Subsequent runs only transit deltas (~50–200 MB typical) and finish in under a minute.

### f. Verify the repo

```bash
restic snapshots                    # list all snapshots, should see the test
restic stats latest                 # size of latest snapshot
restic check                        # repo integrity check (metadata only)
```

## Restore

### Single file from local backup (most common)

```bash
# Find the date and service
ls /mnt/personal/backups/

# Copy what you need
cp /mnt/personal/backups/2026-04-29/sonarr-config/config.xml \
   ~/workspace/home-server/torrent/sonarr/config/config.xml
```

### Restore Postgres from local

```bash
# Recreate the DB and load the dump
docker exec -i immich-postgres pg_restore \
    -U "$DB_USERNAME" -d "$DB_DATABASE_NAME" --clean --if-exists \
    < /mnt/personal/backups/2026-04-29/immich-postgres.dump
```

### Restore from offsite (disaster recovery)

After fresh OS install + `setup.md` phases 1–4 + .env restore:

```bash
sudo apt install -y restic
source .env

# What's in the repo?
restic snapshots
restic snapshots --latest 1

# Restore the latest snapshot to /tmp first (safety: don't overwrite live paths)
restic restore latest --target /tmp/restore

# Inspect, then move into place
ls /tmp/restore/mnt/personal/photos
sudo rsync -aHAX /tmp/restore/mnt/personal/photos/ /mnt/personal/photos/
sudo rsync -aHAX /tmp/restore/mnt/personal/documents/ /mnt/personal/documents/
# Restore vaultwarden, rmfakecloud similarly
# Restore postgres dumps:
docker exec -i immich-postgres pg_restore \
    -U "$DB_USERNAME" -d "$DB_DATABASE_NAME" --clean --if-exists \
    < /tmp/restore/mnt/personal/backups/<date>/immich-postgres.dump
```

### Decrypting env.gpg during disaster recovery

If you've lost the server entirely, restore `env.gpg` from B2 and decrypt:

```bash
restic restore latest --target /tmp/restore --include env.gpg
gpg --decrypt --batch --passphrase "$BACKUP_GPG_PASSPHRASE" \
    /tmp/restore/.../env.gpg > .env
# BACKUP_GPG_PASSPHRASE comes from your password manager — that's why it lives there
```

Then re-run the rest of `setup.md` to reconstitute the service stack.

## Quarterly drill

Schedule a calendar reminder for the first of every quarter to:

1. Pick a small file from `/mnt/personal/documents`
2. Restore it from B2 via `restic restore latest --include <path> --target /tmp/restore-test`
3. Diff against current
4. Run `restic check` (or `restic check --read-data-subset 5%` once a year)

If those all pass, the offsite tier is real.

## Costs

At current pricing (~25 GB):

| Component | $/year |
|-----------|--------|
| Backblaze B2 storage (~25 GB) | ~$1.80 |
| Egress during normal operation | $0 (no reads) |
| Egress during one full disaster restore | ~$0.25 (free up to 3× monthly storage) |
| **Total** | **~$2/year** |

Scales linearly with data — at 100 GB you're at ~$7/year. The Immich library is the main growth driver; expect 2–5 GB/year of new photos for a typical family.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Offsite backup skipped" in log | env vars not set | Check `.env` has `RESTIC_REPOSITORY` + `RESTIC_PASSWORD`; cron's environment differs from interactive shell, so the script sources `.env` itself — confirm the lines have `export` |
| `restic init` fails with "Fatal: ... 401" | B2 application key wrong or scoped to wrong bucket | Regenerate key in B2, scope to the specific bucket, copy `keyID` AND `applicationKey` |
| `restic backup` fails with "Fatal: ... is locked" | Previous run still holding the lock | `restic unlock` (only after confirming no concurrent run) |
| First backup is taking hours | Initial upload of full ~25 GB | Normal — let it run. Subsequent runs are <1 min |
| "restic forget --prune failed (Object Lock)" | Object Lock retention blocks delete | Expected — lock prevents pruning until retention expires; manual prune later if needed |
