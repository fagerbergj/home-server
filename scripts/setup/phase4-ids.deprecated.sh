#!/bin/bash
# DEPRECATED: original PUID/PGID patcher. Had no preflight checks, so it would
# silently write empty IDs into compose files if a user or group was missing.
# Replaced by scripts/setup/phase4-ids.sh, which validates all required
# accounts/groups before touching any file.
# Kept in-repo as a rollback reference during the HBA + ZFS migration;
# delete once M8 verification has been stable for ≥48h.

set -e

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

# Look up IDs
PLEX_UID=$(id -u plex)
IMMICH_UID=$(id -u immich)
QBITTORRENT_UID=$(id -u qbittorrent)
SONARR_UID=$(id -u sonarr)
RADARR_UID=$(id -u radarr)

PLEX_RO_GID=$(getent group plex-ro | cut -d: -f3)
PLEX_RW_GID=$(getent group plex-rw | cut -d: -f3)
PERSONAL_RW_GID=$(getent group personal-rw | cut -d: -f3)

echo "plex uid:          $PLEX_UID"
echo "immich uid:        $IMMICH_UID"
echo "qbittorrent uid:   $QBITTORRENT_UID"
echo "sonarr uid:        $SONARR_UID"
echo "radarr uid:        $RADARR_UID"
echo "plex-ro gid:       $PLEX_RO_GID"
echo "plex-rw gid:       $PLEX_RW_GID"
echo "personal-rw gid:   $PERSONAL_RW_GID"

# Update compose files
sed -i "s|PUID=<plex-uid>|PUID=$PLEX_UID|" "$REPO_ROOT/plex/docker-compose.yml"
sed -i "s|PGID=<plex-ro-gid>|PGID=$PLEX_RO_GID|" "$REPO_ROOT/plex/docker-compose.yml"

sed -i "s|PUID=<immich-uid>|PUID=$IMMICH_UID|" "$REPO_ROOT/photos/docker-compose.yml"
sed -i "s|PGID=<personal-rw-gid>|PGID=$PERSONAL_RW_GID|" "$REPO_ROOT/photos/docker-compose.yml"

sed -i "s|PUID=<qbittorrent-uid>|PUID=$QBITTORRENT_UID|" "$REPO_ROOT/torrent/docker-compose.yml"
sed -i "s|PUID=<sonarr-uid>|PUID=$SONARR_UID|" "$REPO_ROOT/torrent/docker-compose.yml"
sed -i "s|PUID=<radarr-uid>|PUID=$RADARR_UID|" "$REPO_ROOT/torrent/docker-compose.yml"
sed -i "s|PGID=<plex-rw-gid>|PGID=$PLEX_RW_GID|" "$REPO_ROOT/torrent/docker-compose.yml"

echo "done — compose files updated"
