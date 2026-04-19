#!/bin/bash
# Phase 4 — Create ZFS pools and mount points.
#
# Reads the device lists from drives.json (produced by phase4-detect-drives.sh)
# and creates:
#   media    — RAIDZ2 across 4× ~26 TB HDDs, mounted at /mnt/media
#   personal — 2-way mirror across 2× ~8 TB HDDs, mounted at /mnt/personal
#
# Also creates the service users, posix groups, and permission layout that the
# docker-compose services rely on (plex-rw/plex-ro/personal-rw).
#
# Idempotent: skips zpool creation if a pool of the same name already exists.
set -euo pipefail

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
CONFIG="${CONFIG:-$SCRIPT_DIR/drives.json}"

if [[ ! -f "$CONFIG" ]]; then
    echo "Error: $CONFIG not found. Run phase4-detect-drives.sh first." >&2
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "Error: jq is required. Install with: sudo apt install -y jq" >&2
    exit 1
fi

if ! command -v zpool &>/dev/null; then
    echo "Error: ZFS tools are required. Install with: sudo apt install -y zfsutils-linux" >&2
    exit 1
fi

echo "=== Phase 4: ZFS Pool Setup ==="
echo ""
echo "Config ($CONFIG):"
cat "$CONFIG"
echo ""

read -rp "Proceed with this config? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborted."
    exit 1
fi
echo ""

# ---------------------------------------------------------------------------
# Read config — devices into bash arrays so word splitting is explicit.
# ---------------------------------------------------------------------------

mapfile -t MEDIA_DEVICES    < <(jq -r '.media_pool.devices[]'    "$CONFIG")
mapfile -t PERSONAL_DEVICES < <(jq -r '.personal_pool.devices[]' "$CONFIG")

if (( ${#MEDIA_DEVICES[@]} != 4 )); then
    echo "Error: media_pool must have exactly 4 devices, got ${#MEDIA_DEVICES[@]}." >&2
    exit 1
fi
if (( ${#PERSONAL_DEVICES[@]} != 2 )); then
    echo "Error: personal_pool must have exactly 2 devices, got ${#PERSONAL_DEVICES[@]}." >&2
    exit 1
fi

# Install acl now — needed for setfacl below. Harmless if already present.
sudo apt install -y acl

# ---------------------------------------------------------------------------
# Create media pool (RAIDZ2)
# ---------------------------------------------------------------------------

if sudo zpool list -H -o name media &>/dev/null; then
    echo "media pool already exists — skipping creation."
else
    echo "Creating media pool with RAIDZ2 layout..."
    printf "  %s\n" "${MEDIA_DEVICES[@]}"
    sudo zpool create -o ashift=12 \
        -O compression=lz4 \
        -O atime=off \
        -O xattr=sa \
        -O acltype=posixacl \
        -O recordsize=1M \
        -O mountpoint=/mnt/media \
        media raidz2 \
        "${MEDIA_DEVICES[@]}"
    echo "Media pool created."
fi
echo ""
sudo zpool status media
echo ""
sudo zfs list -r media
echo ""

# Content subdirs the services expect (see docker-compose bind mounts).
# Flat layout on RAIDZ2 — the legacy plex01/plex02 split existed only because
# the old setup had two separate ext4 drives.
sudo mkdir -p /mnt/media/{movies,shows,audiobooks,downloads}

sudo chown -R root:plex-rw /mnt/media
sudo chmod -R 2775         /mnt/media

# plex-ro is the read-only access group for the Plex server itself — it can
# read media without being able to write/delete. posix ACL so new files
# created by plex-rw members automatically inherit r-x for plex-ro.
sudo setfacl -R -m    g:plex-ro:rx /mnt/media
sudo setfacl -R -d -m g:plex-ro:rx /mnt/media

echo "Media pool datasets and permissions set."
echo ""

# ---------------------------------------------------------------------------
# Create personal pool (mirror)
# ---------------------------------------------------------------------------

if sudo zpool list -H -o name personal &>/dev/null; then
    echo "personal pool already exists — skipping creation."
else
    echo "Creating personal pool with 2-way mirror..."
    printf "  %s\n" "${PERSONAL_DEVICES[@]}"
    sudo zpool create -o ashift=12 \
        -O compression=lz4 \
        -O atime=off \
        -O xattr=sa \
        -O acltype=posixacl \
        -O mountpoint=/mnt/personal \
        personal \
        mirror "${PERSONAL_DEVICES[@]}"
    echo "Personal pool created."
fi
echo ""
sudo zpool status personal
echo ""
sudo zfs list -r personal
echo ""

for ds in personal/photos personal/documents personal/backups; do
    if ! sudo zfs list -H -o name "$ds" &>/dev/null; then
        sudo zfs create "$ds"
    fi
done

sudo chown -R root:personal-rw /mnt/personal
sudo chmod -R 2775             /mnt/personal

echo "Personal pool datasets and permissions set."
echo ""

# ---------------------------------------------------------------------------
# Service users and groups
# ---------------------------------------------------------------------------

echo "Creating service users and groups..."

for user in plex immich minecraft qbittorrent audiobookshelf; do
    if ! getent passwd "$user" &>/dev/null; then
        sudo useradd -r -s /sbin/nologin "$user"
        echo "  Created user: $user"
    else
        echo "  User $user already exists, skipping"
    fi
done

for group in plex-rw plex-ro personal-rw personal-ro; do
    if ! getent group "$group" &>/dev/null; then
        sudo groupadd "$group"
        echo "  Created group: $group"
    else
        echo "  Group $group already exists, skipping"
    fi
done

sudo usermod -aG plex-rw     qbittorrent
sudo usermod -aG plex-rw     jason-server
sudo usermod -aG plex-ro     plex
sudo usermod -aG plex-ro     audiobookshelf
sudo usermod -aG personal-rw immich
sudo usermod -aG personal-rw jason-server
echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "=== Phase 4 complete ==="
echo ""
echo "ZFS pools created:"
echo "  - media    (RAIDZ2 with 4 drives)  → /mnt/media"
echo "  - personal (mirror  with 2 drives) → /mnt/personal"
echo ""
echo "Next: run scripts/setup/phase4-ids.sh to patch PUID/PGID into compose files."
echo ""
echo "Current IDs (for reference):"
printf "  %-22s %s\n" "PUID (plex):"           "$(id -u plex)"
printf "  %-22s %s\n" "PUID (immich):"         "$(id -u immich)"
printf "  %-22s %s\n" "PUID (minecraft):"      "$(id -u minecraft)"
printf "  %-22s %s\n" "PUID (qbittorrent):"    "$(id -u qbittorrent)"
printf "  %-22s %s\n" "PUID (audiobookshelf):" "$(id -u audiobookshelf)"
printf "  %-22s %s\n" "PGID (plex-rw):"        "$(getent group plex-rw     | cut -d: -f3)"
printf "  %-22s %s\n" "PGID (plex-ro):"        "$(getent group plex-ro     | cut -d: -f3)"
printf "  %-22s %s\n" "PGID (personal-rw):"    "$(getent group personal-rw | cut -d: -f3)"
