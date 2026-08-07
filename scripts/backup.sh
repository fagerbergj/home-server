#!/usr/bin/env bash
# backup.sh — backs up key service data to /mnt/personal/backups
#
# What gets backed up:
#   - Vaultwarden (passwords)       passwords/data/
#   - Immich postgres DB            pg_dump via docker exec
#   - Minecraft world               minecraft/data/
#   - Grafana                       monitoring/grafana/
#   - Prometheus metrics            monitoring/prometheus/data/
#   - rmfakecloud (notes)           notes/rmfakecloud-data/
#   - Plex config/DB                plex/config/  (excludes Cache/ — can be GBs of thumbnails)
#   - Audiobookshelf config         audiobooks/config/ + audiobooks/metadata/
#   - Sonarr config                 torrent/sonarr/config/
#   - Radarr config                 torrent/radarr/config/
#   - Prowlarr config               torrent/prowlarr/config/
#   - qBittorrent config            torrent/config/
#   - Authentik postgres DB         pg_dump via docker exec
#   - Authentik media/certs         api/data/authentik-media/ + api/data/authentik-certs/
#   - env files                     root .env + every <stack>/.env (gpg-encrypted)
#   - System config                 /etc/fstab, /etc/mdadm/mdadm.conf
#   - Root crontab
#
# Photos and documents live on the personal pool (mirrored ZFS) — protected
# locally, but pushed offsite by the optional restic step below since they're
# the irreplaceable bits.
# Plex/audiobook media files live on the media pool — not backed up here.
#
# Env files are encrypted with gpg before writing. Requires BACKUP_GPG_PASSPHRASE
# in .env or environment. Falls back to skipping if not set.
#
# Offsite backup (optional, additive): if RESTIC_REPOSITORY and RESTIC_PASSWORD
# are set in .env, the irreplaceable subset (photos, documents, postgres dumps,
# vaultwarden data, rmfakecloud, env.tar.gpg) is pushed to a restic repo after the
# local backup finishes. Works with any restic backend — S3, Backblaze B2,
# rsync.net, SFTP. Restic handles encryption, dedup, and retention.
#
# Usage:
#   ./scripts/backup.sh
#
# Run from the home-server repo root. Reads ../.env (one level up from
# each service) for Immich postgres credentials.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="/mnt/personal/backups/$(date +%Y-%m-%d)"
ENV_FILE="$REPO_ROOT/.env"

log() { echo "[$(date +%H:%M:%S)] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# ── Preflight ──────────────────────────────────────────────────────────────

[[ -d /mnt/personal ]] || die "/mnt/personal is not mounted"
[[ -f "$ENV_FILE" ]] || die ".env not found at $ENV_FILE"

# Root first, then each stack's own file - the pg_dump credentials below moved
# into photos/.env, so sourcing only the root would break once it is pruned.
# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
for f in "$REPO_ROOT"/*/.env; do [[ -f "$f" ]] && source "$f"; done
set +a

mkdir -p "$DEST"
log "Backing up to $DEST"

# ── Vaultwarden ───────────────────────────────────────────────────────────

log "Vaultwarden..."
rsync -a --delete "$REPO_ROOT/passwords/data/" "$DEST/vaultwarden/"

# ── Immich postgres ───────────────────────────────────────────────────────

log "Immich postgres (pg_dump)..."
docker exec immich-postgres pg_dump \
    -U "$DB_USERNAME" \
    -d "$DB_DATABASE_NAME" \
    --format=custom \
    > "$DEST/immich-postgres.dump"

# ── Minecraft world ───────────────────────────────────────────────────────

log "Minecraft world..."
# Warn the server before copying so chunk data is flushed
docker exec minecraft rcon-cli save-all 2>/dev/null || true
sleep 3
rsync -a --delete "$REPO_ROOT/minecraft/data/" "$DEST/minecraft/"

# ── Grafana ───────────────────────────────────────────────────────────────

log "Grafana..."
rsync -a --delete "$REPO_ROOT/monitoring/grafana/" "$DEST/grafana/"

# ── Prometheus ────────────────────────────────────────────────────────────

log "Prometheus..."
rsync -a --delete "$REPO_ROOT/monitoring/prometheus/data/" "$DEST/prometheus/"

# ── rmfakecloud (notes) ───────────────────────────────────────────────────

log "rmfakecloud..."
rsync -a --delete "$REPO_ROOT/notes/rmfakecloud-data/" "$DEST/rmfakecloud/"

# ── Plex ──────────────────────────────────────────────────────────────────

log "Plex config..."
# Exclude Cache — it's regenerable thumbnails and can be many GBs
rsync -a --delete \
    --exclude="Cache/" \
    "$REPO_ROOT/plex/config/" "$DEST/plex-config/"

# ── Audiobookshelf ────────────────────────────────────────────────────────

log "Audiobookshelf..."
rsync -a --delete "$REPO_ROOT/audiobooks/config/" "$DEST/audiobookshelf-config/"
rsync -a --delete "$REPO_ROOT/audiobooks/metadata/" "$DEST/audiobookshelf-metadata/"

# ── Sonarr / Radarr ───────────────────────────────────────────────────────

log "Sonarr..."
rsync -a --delete "$REPO_ROOT/torrent/sonarr/config/" "$DEST/sonarr-config/"

log "Radarr..."
rsync -a --delete "$REPO_ROOT/torrent/radarr/config/" "$DEST/radarr-config/"

log "Prowlarr..."
rsync -a --delete "$REPO_ROOT/torrent/prowlarr/config/" "$DEST/prowlarr-config/"

log "qBittorrent..."
rsync -a --delete "$REPO_ROOT/torrent/config/" "$DEST/qbittorrent-config/"

# ── Authentik ─────────────────────────────────────────────────────────────

log "Authentik postgres (pg_dump)..."
docker exec authentik-postgres pg_dump \
    -U "$AUTHENTIK_DB_USER" \
    -d "$AUTHENTIK_DB_NAME" \
    --format=custom \
    > "$DEST/authentik-postgres.dump"

log "Authentik media and certs..."
rsync -a --delete "$REPO_ROOT/api/data/authentik-media/" "$DEST/authentik-media/"
rsync -a --delete "$REPO_ROOT/api/data/authentik-certs/" "$DEST/authentik-certs/"

# ── .env (encrypted) ──────────────────────────────────────────────────────

log "env files (encrypted)..."
if command -v gpg &>/dev/null && [[ -n "${BACKUP_GPG_PASSPHRASE:-}" ]]; then
    # Each stack owns its secrets now, so the root .env alone is not a full
    # restore. Paths are stored repo-relative so a restore lands them back.
    mapfile -t ENV_FILES < <(cd "$REPO_ROOT" && ls .env */.env 2>/dev/null)
    [[ ${#ENV_FILES[@]} -gt 0 ]] || die "no env files found under $REPO_ROOT"
    tar -C "$REPO_ROOT" -cf - "${ENV_FILES[@]}" \
      | gpg --batch --yes --passphrase "$BACKUP_GPG_PASSPHRASE" \
            --symmetric --cipher-algo AES256 \
            --output "$DEST/env.tar.gpg"
    log "  ${#ENV_FILES[@]} env file(s) encrypted to env.tar.gpg: ${ENV_FILES[*]}"
else
    log "  WARNING: skipping env backup — set BACKUP_GPG_PASSPHRASE to enable"
fi

# ── System config ─────────────────────────────────────────────────────────

log "System config..."
mkdir -p "$DEST/system"
cp /etc/fstab "$DEST/system/fstab"
[[ -f /etc/mdadm/mdadm.conf ]] && cp /etc/mdadm/mdadm.conf "$DEST/system/mdadm.conf"
sudo crontab -l > "$DEST/system/root-crontab" 2>/dev/null || true

# ── Summary ───────────────────────────────────────────────────────────────

log "Done. Backup size: $(du -sh "$DEST" | cut -f1)"
ls -lh "$DEST"

# ── Offsite (restic — provider-agnostic, uses RESTIC_REPOSITORY URL) ──────
#
# Pushes only the irreplaceable subset (photos, documents, postgres dumps,
# vaultwarden, rmfakecloud, env.tar.gpg) — not the full local backup. Restic
# handles encryption, deduplication, and retention.
#
# One-time setup before this runs cleanly:
#   sudo apt install -y restic
#   restic init                         # bootstrap the remote repo
#
# Required env vars in .env (sourced above):
#   RESTIC_REPOSITORY   e.g. b2:jason-fagerberg:home-server
#   RESTIC_PASSWORD     long random string — losing this means losing the backups
#   For B2:  B2_ACCOUNT_ID + B2_ACCOUNT_KEY (the application key, not master)
#   For S3:  AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY + AWS_DEFAULT_REGION
#
# If the env vars aren't set, this section is a no-op.

if [[ -n "${RESTIC_REPOSITORY:-}" && -n "${RESTIC_PASSWORD:-}" ]]; then
    if ! command -v restic &>/dev/null; then
        log "WARNING: RESTIC_REPOSITORY set but 'restic' not installed (sudo apt install -y restic) — skipping offsite"
    else
        log "Offsite backup (restic → $RESTIC_REPOSITORY)..."

        OFFSITE_SOURCES=(
            /mnt/personal/photos
            /mnt/personal/documents
            "$DEST/immich-postgres.dump"
            "$DEST/authentik-postgres.dump"
            "$DEST/vaultwarden"
            "$DEST/rmfakecloud"
            "$DEST/minecraft"
        )
        [[ -f "$DEST/env.tar.gpg" ]] && OFFSITE_SOURCES+=("$DEST/env.tar.gpg")

        log "  Sources (size each):"
        for src in "${OFFSITE_SOURCES[@]}"; do
            if [[ -e "$src" ]]; then
                log "    $(du -sh "$src" 2>/dev/null | cut -f1)\t$src"
            else
                log "    (missing)\t$src"
            fi
        done

        # Backup with verbose progress so cron logs show what's happening
        # during long initial uploads. --verbose=1 shows the per-stage
        # progress (Files/Dirs/Added) without per-file noise.
        START=$SECONDS
        log "  Starting restic backup..."
        if restic backup \
            --verbose=1 \
            --tag automated \
            --tag "$(date +%Y-%m-%d)" \
            "${OFFSITE_SOURCES[@]}"; then
            ELAPSED=$((SECONDS - START))
            log "  Restic backup ok in ${ELAPSED}s."

            # Forget: drop old snapshot references. Always safe (only edits
            # repo metadata, never deletes pack files). Should always succeed.
            log "  Forgetting old snapshots (keep daily-7, weekly-4, monthly-12)..."
            restic forget \
                --keep-daily 7 \
                --keep-weekly 4 \
                --keep-monthly 12 \
                || log "  WARNING: restic forget failed (this is unusual — investigate)"

            # Prune: delete pack files no longer referenced by any snapshot.
            # With B2 Object Lock enabled, packs younger than the lock window
            # (typically 3 days) cannot be deleted yet — restic logs warnings
            # but the operation still partially succeeds. Older packs are
            # freed; locked ones get cleaned up on subsequent prune runs once
            # their lock expires. Net effect: ~3 days of "extra" data lingers.
            log "  Pruning unreferenced data (locked packs will be skipped)..."
            if restic prune 2>&1 | tee /tmp/restic-prune-$$.log; then
                : # prune cleanly succeeded
            elif grep -qi "legal hold\|retention\|object lock\|access denied" /tmp/restic-prune-$$.log; then
                log "  Note: some packs still under Object Lock — will be pruned on a future run (expected behavior)"
            else
                log "  WARNING: restic prune failed for non-Object-Lock reason — check above output"
            fi
            rm -f /tmp/restic-prune-$$.log

            log "  Repo stats after run:"
            restic stats latest --mode raw-data 2>/dev/null | sed 's/^/    /' || true
            log "  Latest offsite snapshot:"
            restic snapshots --latest 1 2>/dev/null | tail -3 || true
        else
            log "  ERROR: restic backup failed — local backup still ok, offsite skipped"
        fi
    fi
else
    log "Offsite backup skipped (set RESTIC_REPOSITORY + RESTIC_PASSWORD in .env to enable)"
fi

# ── Retention — keep only the 3 most recent backups ───────────────────────

BACKUP_ROOT="/mnt/personal/backups"
MAX_BACKUPS=3

mapfile -t OLD_BACKUPS < <(ls -1d "$BACKUP_ROOT"/????-??-?? 2>/dev/null | sort | head -n -$MAX_BACKUPS)
if [[ ${#OLD_BACKUPS[@]} -gt 0 ]]; then
    log "Pruning ${#OLD_BACKUPS[@]} old backup(s)..."
    for dir in "${OLD_BACKUPS[@]}"; do
        log "  Removing $dir"
        rm -rf "$dir"
    done
fi
