#!/usr/bin/env bash
# backup.sh — backs up key service data to /mnt/personal01/backups
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
#   - .env                          repo root .env (gpg-encrypted)
#   - System config                 /etc/fstab, /etc/mdadm/mdadm.conf
#   - Root crontab
#
# Photos are already on personal01 — no need to back them up.
# Plex/audiobook media files are on plex01/plex02 — not backed up here.
#
# .env is encrypted with gpg before writing. Requires GPG_RECIPIENT in .env
# or set in environment. Falls back to symmetric encryption if not set.
#
# Usage:
#   ./scripts/backup.sh
#
# Run from the home-server repo root. Reads ../.env (one level up from
# each service) for Immich postgres credentials.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="/mnt/personal01/backups/$(date +%Y-%m-%d)"
ENV_FILE="$REPO_ROOT/.env"

log() { echo "[$(date +%H:%M:%S)] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# ── Preflight ──────────────────────────────────────────────────────────────

[[ -d /mnt/personal01 ]] || die "/mnt/personal01 is not mounted"
[[ -f "$ENV_FILE" ]] || die ".env not found at $ENV_FILE"

# Load DB credentials from .env
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

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

log ".env (encrypted)..."
if command -v gpg &>/dev/null && [[ -n "${BACKUP_GPG_PASSPHRASE:-}" ]]; then
    gpg --batch --yes --passphrase "$BACKUP_GPG_PASSPHRASE" \
        --symmetric --cipher-algo AES256 \
        --output "$DEST/env.gpg" \
        "$ENV_FILE"
    log "  .env encrypted to env.gpg"
else
    log "  WARNING: skipping .env backup — set BACKUP_GPG_PASSPHRASE in .env to enable"
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

# ── Retention — keep only the 3 most recent backups ───────────────────────

BACKUP_ROOT="/mnt/personal01/backups"
MAX_BACKUPS=3

mapfile -t OLD_BACKUPS < <(ls -1d "$BACKUP_ROOT"/????-??-?? 2>/dev/null | sort | head -n -$MAX_BACKUPS)
if [[ ${#OLD_BACKUPS[@]} -gt 0 ]]; then
    log "Pruning ${#OLD_BACKUPS[@]} old backup(s)..."
    for dir in "${OLD_BACKUPS[@]}"; do
        log "  Removing $dir"
        rm -rf "$dir"
    done
fi
