#!/bin/bash
# Phase 4 — Mount Drives, RAID 1, Users, and Permissions
# Reads drives.json — run phase4-detect-drives.sh first to generate it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$SCRIPT_DIR/drives.json"

if [[ ! -f "$CONFIG" ]]; then
    echo "Error: $CONFIG not found. Run phase4-detect-drives.sh first."
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "Error: jq is required. Install with: sudo apt install -y jq"
    exit 1
fi

echo "=== Phase 4: Drive Setup ==="
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
# Read config
# ---------------------------------------------------------------------------

PLEX01_DEV=$(jq -r '.plex01.device' "$CONFIG")
PLEX01_PRESERVE=$(jq -r '.plex01.preserve' "$CONFIG")
PLEX02_DEV=$(jq -r '.plex02.device // empty' "$CONFIG")
PLEX02_PRESERVE=$(jq -r '.plex02.preserve // "false"' "$CONFIG")
RAID_PRIMARY=$(jq -r '.personal01.raid_primary' "$CONFIG")
RAID_SECONDARY=$(jq -r '.personal01.raid_secondary' "$CONFIG")

# ---------------------------------------------------------------------------
# Mount plex01
# ---------------------------------------------------------------------------

if [[ "$PLEX01_PRESERVE" == "true" ]]; then
    echo "plex01 ($PLEX01_DEV) — preserving existing data, skipping format."
else
    echo "Formatting $PLEX01_DEV as ext4..."
    sudo mkfs.ext4 -F "$PLEX01_DEV"
fi

PLEX01_UUID=$(sudo blkid -s UUID -o value "$PLEX01_DEV")
sudo mkdir -p /mnt/plex01
if ! grep -q "/mnt/plex01" /etc/fstab; then
    echo "UUID=$PLEX01_UUID   /mnt/plex01   ext4   defaults   0   2" | sudo tee -a /etc/fstab
fi
sudo mount -a
echo "plex01 mounted."
echo ""

# ---------------------------------------------------------------------------
# Mount plex02 (optional)
# ---------------------------------------------------------------------------

if [[ -n "$PLEX02_DEV" ]]; then
    if [[ "$PLEX02_PRESERVE" == "true" ]]; then
        echo "plex02 ($PLEX02_DEV) — preserving existing data, skipping format."
    else
        echo "Formatting $PLEX02_DEV as ext4 (plex02)..."
        sudo mkfs.ext4 -F "$PLEX02_DEV"
    fi

    PLEX02_UUID=$(sudo blkid -s UUID -o value "$PLEX02_DEV")
    sudo mkdir -p /mnt/plex02
    if ! grep -q "/mnt/plex02" /etc/fstab; then
        echo "UUID=$PLEX02_UUID   /mnt/plex02   ext4   defaults   0   2" | sudo tee -a /etc/fstab
    fi
    sudo mount -a
    echo "plex02 mounted."
    echo ""
fi

# ---------------------------------------------------------------------------
# Create RAID 1 for personal01
# ---------------------------------------------------------------------------

echo "Creating RAID 1 array from $RAID_PRIMARY (primary) and $RAID_SECONDARY (secondary)..."
# --force overwrites any existing RAID metadata or filesystem signatures on the drives
sudo mdadm --create --force /dev/md0 --level=1 --raid-devices=2 "$RAID_PRIMARY" "$RAID_SECONDARY"

echo ""
echo "RAID sync started. This takes ~2 hours for 1TB drives."
echo "Monitor progress with: watch cat /proc/mdstat"
echo ""
read -rp "Press ENTER once sync is complete to continue..."

sudo mkfs.ext4 /dev/md0
sudo mkdir -p /mnt/personal01
sudo mount /dev/md0 /mnt/personal01

sudo mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf
sudo update-initramfs -u

MD0_UUID=$(sudo blkid -s UUID -o value /dev/md0)
if ! grep -q "/mnt/personal01" /etc/fstab; then
    echo "UUID=$MD0_UUID   /mnt/personal01   ext4   defaults   0   2" | sudo tee -a /etc/fstab
fi
echo "personal01 mounted."
echo ""

# ---------------------------------------------------------------------------
# Service users and groups
# ---------------------------------------------------------------------------

echo "Creating service users and groups..."

for user in plex immich minecraft qbittorrent; do
    if ! id "$user" &>/dev/null; then
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

sudo usermod -aG plex-rw qbittorrent
sudo usermod -aG plex-rw jason
sudo usermod -aG plex-ro plex
sudo usermod -aG personal-rw immich
sudo usermod -aG personal-rw jason
echo ""

# ---------------------------------------------------------------------------
# Folder structure and permissions
# ---------------------------------------------------------------------------

echo "Setting up folder structure and permissions..."
sudo apt install -y acl

sudo mkdir -p /mnt/plex01/movies /mnt/plex01/shows
sudo chown -R root:plex-rw /mnt/plex01
sudo chmod -R 2775 /mnt/plex01
sudo setfacl -R -m g:plex-ro:rx /mnt/plex01

sudo mkdir -p /mnt/personal01/photos
sudo chown -R root:personal-rw /mnt/personal01
sudo chmod -R 2775 /mnt/personal01

if [[ -n "$PLEX02_DEV" ]]; then
    sudo mkdir -p /mnt/plex02/movies /mnt/plex02/shows
    sudo chown -R root:plex-rw /mnt/plex02
    sudo chmod -R 2775 /mnt/plex02
    sudo setfacl -R -m g:plex-ro:rx /mnt/plex02
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "=== Phase 4 complete ==="
echo ""
echo "Update these values in each docker-compose.yml:"
echo ""
printf "  %-20s %s\n" "PUID (plex):"        "$(id -u plex)"
printf "  %-20s %s\n" "PUID (immich):"      "$(id -u immich)"
printf "  %-20s %s\n" "PUID (minecraft):"   "$(id -u minecraft)"
printf "  %-20s %s\n" "PUID (qbittorrent):" "$(id -u qbittorrent)"
printf "  %-20s %s\n" "PGID (plex-rw):"     "$(getent group plex-rw | cut -d: -f3)"
printf "  %-20s %s\n" "PGID (plex-ro):"     "$(getent group plex-ro | cut -d: -f3)"
printf "  %-20s %s\n" "PGID (personal-rw):" "$(getent group personal-rw | cut -d: -f3)"
