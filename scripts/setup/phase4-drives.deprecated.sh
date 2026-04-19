#!/bin/bash
# DEPRECATED: creates mdadm RAID 1 arrays and ext4 filesystems for the old
# plex01/plex02/plex03 + personal01 layout. Replaced by scripts/setup/phase4-drives.sh,
# which creates the ZFS media (RAIDZ2) and personal (mirror) pools.
# Kept in-repo as a rollback reference during the HBA + ZFS migration;
# delete once M8 verification has been stable for ≥48h.
set -euo pipefail

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
CONFIG="$SCRIPT_DIR/drives.json"

if [[ ! -f "$CONFIG" ]]; then
    echo "Error: $CONFIG not found. Run phase4-detect-drives.sh first."
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "Error: jq is required. Install with: sudo apt install -y jq"
    exit 1
fi

if ! command -v mdadm &>/dev/null; then
    echo "Error: mdadm is required. Install with: sudo apt install -y mdadm"
    exit 1
fi

echo "=== Phase 4: Old mdadm RAID Setup (DEPRECATED) ==="
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
PLEX03_DEV=$(jq -r '.plex03.device // empty' "$CONFIG")
PLEX03_PRESERVE=$(jq -r '.plex03.preserve // "false"' "$CONFIG")
PERSONAL01_DEV=$(jq -r '.personal01.device' "$CONFIG")
PERSONAL01_PRESERVE=$(jq -r '.personal01.preserve' "$CONFIG")

# ---------------------------------------------------------------------------
# Create personal01 RAID 1 array
# ---------------------------------------------------------------------------

echo "Creating personal01 RAID 1 array..."
echo "Devices: $PERSONAL01_DEV"

if [[ "$PERSONAL01_PRESERVE" == "true" ]]; then
    echo "Preserving existing personal01 array..."
    # Just ensure it's assembled
    sudo mdadm --assemble --force /dev/md0 $PERSONAL01_DEV
else
    # Create new RAID 1 array
    sudo mdadm --create /dev/md0 \
        --level=1 \
        --raid-devices=2 \
        $PERSONAL01_DEV
fi

echo "personal01 RAID 1 array created."
echo ""
sudo mdadm --detail /dev/md0
echo ""

# ---------------------------------------------------------------------------
# Format and mount personal01
# ---------------------------------------------------------------------------

echo "Formatting personal01 with ext4..."
sudo mkfs.ext4 -F /dev/md0

echo "Mounting personal01..."
sudo mkdir -p /mnt/personal01
sudo mount /dev/md0 /mnt/personal01

# Add to fstab
echo "/dev/md0 /mnt/personal01 ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab

echo "personal01 mounted."
echo ""

# ---------------------------------------------------------------------------
# Create plex01 and plex02 arrays if specified
# ---------------------------------------------------------------------------

if [[ -n "$PLEX01_DEV" ]]; then
    echo "Creating plex01 RAID 1 array..."
    echo "Devices: $PLEX01_DEV"
    
    if [[ "$PLEX01_PRESERVE" == "true" ]]; then
        echo "Preserving existing plex01 array..."
        sudo mdadm --assemble --force /dev/md1 $PLEX01_DEV
    else
        sudo mdadm --create /dev/md1 \
            --level=1 \
            --raid-devices=2 \
            $PLEX01_DEV
    fi
    
    echo "plex01 RAID 1 array created."
    echo ""
    sudo mdadm --detail /dev/md1
    echo ""
    
    echo "Formatting plex01 with ext4..."
    sudo mkfs.ext4 -F /dev/md1
    
    echo "Mounting plex01..."
    sudo mkdir -p /mnt/plex01
    sudo mount /dev/md1 /mnt/plex01
    
    # Add to fstab
    echo "/dev/md1 /mnt/plex01 ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
    
    echo "plex01 mounted."
    echo ""
fi

if [[ -n "$PLEX02_DEV" ]]; then
    echo "Creating plex02 RAID 1 array..."
    echo "Devices: $PLEX02_DEV"
    
    if [[ "$PLEX02_PRESERVE" == "true" ]]; then
        echo "Preserving existing plex02 array..."
        sudo mdadm --assemble --force /dev/md2 $PLEX02_DEV
    else
        sudo mdadm --create /dev/md2 \
            --level=1 \
            --raid-devices=2 \
            $PLEX02_DEV
    fi
    
    echo "plex02 RAID 1 array created."
    echo ""
    sudo mdadm --detail /dev/md2
    echo ""
    
    echo "Formatting plex02 with ext4..."
    sudo mkfs.ext4 -F /dev/md2
    
    echo "Mounting plex02..."
    sudo mkdir -p /mnt/plex02
    sudo mount /dev/md2 /mnt/plex02
    
    # Add to fstab
    echo "/dev/md2 /mnt/plex02 ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
    
    echo "plex02 mounted."
    echo ""
fi

if [[ -n "$PLEX03_DEV" ]]; then
    echo "Creating plex03 RAID 1 array..."
    echo "Devices: $PLEX03_DEV"
    
    if [[ "$PLEX03_PRESERVE" == "true" ]]; then
        echo "Preserving existing plex03 array..."
        sudo mdadm --assemble --force /dev/md3 $PLEX03_DEV
    else
        sudo mdadm --create /dev/md3 \
            --level=1 \
            --raid-devices=2 \
            $PLEX03_DEV
    fi
    
    echo "plex03 RAID 1 array created."
    echo ""
    sudo mdadm --detail /dev/md3
    echo ""
    
    echo "Formatting plex03 with ext4..."
    sudo mkfs.ext4 -F /dev/md3
    
    echo "Mounting plex03..."
    sudo mkdir -p /mnt/plex03
    sudo mount /dev/md3 /mnt/plex03
    
    # Add to fstab
    echo "/dev/md3 /mnt/plex03 ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
    
    echo "plex03 mounted."
    echo ""
fi

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

sudo usermod -aG plex-rw qbittorrent
sudo usermod -aG plex-rw jason-server
sudo usermod -aG plex-ro plex
sudo usermod -aG plex-ro audiobookshelf
sudo usermod -aG personal-rw immich
sudo usermod -aG personal-rw jason-server
echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "=== Phase 4 complete (OLD SETUP) ==="
echo ""
echo "Old mdadm RAID arrays created:"
echo "  - personal01 (RAID 1 with 2 drives)"
echo "  - plex01 (RAID 1 with 2 drives) - if specified"
echo "  - plex02 (RAID 1 with 2 drives) - if specified"
echo "  - plex03 (RAID 1 with 2 drives) - if specified"
echo ""
echo "Mount points:"
echo "  - /mnt/personal01 (personal01 RAID 1)"
echo "  - /mnt/plex01 (plex01 RAID 1) - if specified"
echo "  - /mnt/plex02 (plex02 RAID 1) - if specified"
echo "  - /mnt/plex03 (plex03 RAID 1) - if specified"
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
printf "  %-20s %s\n" "PUID (audiobookshelf):" "$(id -u audiobookshelf)"