#!/bin/bash
# Phase 4 — Patch PUID/PGID values into each service's docker-compose.yml.
#
# Looks up the actual UID/GID that phase4-drives.sh created, then rewrites the
# matching `PUID=...` / `PGID=...` line in each compose file. Matches are
# anchored on the `# run: id <user>` / `# run: getent group <group>` comments
# that document what each line is for — idempotent and safe to re-run.
#
# Preflight: fails before touching any file if a user or group is missing,
# or if an expected compose file doesn't exist.
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

REQUIRED_USERS=(plex immich qbittorrent sonarr radarr audiobookshelf)
REQUIRED_GROUPS=(plex-rw plex-ro personal-rw)

COMPOSE_PLEX="$REPO_ROOT/plex/docker-compose.yml"
COMPOSE_PHOTOS="$REPO_ROOT/photos/docker-compose.yml"
COMPOSE_TORRENT="$REPO_ROOT/torrent/docker-compose.yml"
REQUIRED_FILES=("$COMPOSE_PLEX" "$COMPOSE_PHOTOS" "$COMPOSE_TORRENT")

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

missing=0
for u in "${REQUIRED_USERS[@]}"; do
    if ! getent passwd "$u" &>/dev/null; then
        echo "Error: user '$u' does not exist — run phase4-drives.sh first." >&2
        missing=1
    fi
done
for g in "${REQUIRED_GROUPS[@]}"; do
    if ! getent group "$g" &>/dev/null; then
        echo "Error: group '$g' does not exist — run phase4-drives.sh first." >&2
        missing=1
    fi
done
for f in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "$f" ]]; then
        echo "Error: compose file not found: $f" >&2
        missing=1
    fi
done
(( missing == 0 )) || exit 1

# ---------------------------------------------------------------------------
# Look up IDs
# ---------------------------------------------------------------------------

PLEX_UID=$(id -u plex)
IMMICH_UID=$(id -u immich)
QBITTORRENT_UID=$(id -u qbittorrent)
SONARR_UID=$(id -u sonarr)
RADARR_UID=$(id -u radarr)

PLEX_RO_GID=$(getent group plex-ro     | cut -d: -f3)
PLEX_RW_GID=$(getent group plex-rw     | cut -d: -f3)
PERSONAL_RW_GID=$(getent group personal-rw | cut -d: -f3)

echo "Resolved IDs:"
printf "  %-22s %s\n" "plex uid:"        "$PLEX_UID"
printf "  %-22s %s\n" "immich uid:"      "$IMMICH_UID"
printf "  %-22s %s\n" "qbittorrent uid:" "$QBITTORRENT_UID"
printf "  %-22s %s\n" "sonarr uid:"      "$SONARR_UID"
printf "  %-22s %s\n" "radarr uid:"      "$RADARR_UID"
printf "  %-22s %s\n" "plex-ro gid:"     "$PLEX_RO_GID"
printf "  %-22s %s\n" "plex-rw gid:"     "$PLEX_RW_GID"
printf "  %-22s %s\n" "personal-rw gid:" "$PERSONAL_RW_GID"
echo ""

# ---------------------------------------------------------------------------
# Patch compose files.
#
# Each rewrite anchors on the `# run: ...` comment already in the file, so
# the pattern uniquely identifies which PUID/PGID line to replace no matter
# what the current value is.
# ---------------------------------------------------------------------------

patch_line() {
    local file="$1" pattern="$2" replacement="$3"
    if ! grep -qE "$pattern" "$file"; then
        echo "Error: pattern not found in $file: $pattern" >&2
        return 1
    fi
    sed -i -E "s|$pattern|$replacement|" "$file"
}

patch_line "$COMPOSE_PLEX" \
    'PUID=[0-9]+ +# run: id plex' \
    "PUID=$PLEX_UID    # run: id plex"
patch_line "$COMPOSE_PLEX" \
    'PGID=[0-9]+ +# run: getent group plex-ro' \
    "PGID=$PLEX_RO_GID # run: getent group plex-ro"

patch_line "$COMPOSE_PHOTOS" \
    'PUID=[0-9]+ +# run: id immich' \
    "PUID=$IMMICH_UID      # run: id immich"
patch_line "$COMPOSE_PHOTOS" \
    'PGID=[0-9]+ +# run: getent group personal-rw' \
    "PGID=$PERSONAL_RW_GID # run: getent group personal-rw"

patch_line "$COMPOSE_TORRENT" \
    'PUID=[0-9]+ +# run: id qbittorrent' \
    "PUID=$QBITTORRENT_UID # run: id qbittorrent"
patch_line "$COMPOSE_TORRENT" \
    'PUID=[0-9]+ +# run: id sonarr' \
    "PUID=$SONARR_UID      # run: id sonarr"
patch_line "$COMPOSE_TORRENT" \
    'PUID=[0-9]+ +# run: id radarr' \
    "PUID=$RADARR_UID      # run: id radarr"
# All three *arr services share plex-rw — three separate lines, same value.
sed -i -E "s|PGID=[0-9]+ +# run: getent group plex-rw|PGID=$PLEX_RW_GID # run: getent group plex-rw|g" \
    "$COMPOSE_TORRENT"

echo "Compose files patched:"
printf "  %s\n" "${REQUIRED_FILES[@]}"
