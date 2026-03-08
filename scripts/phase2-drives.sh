#!/bin/bash
# Phase 2 — Mount Drives, RAID 1, Users, and Permissions
set -euo pipefail

echo "=== Phase 2: Drive Setup ==="
echo ""

# ---------------------------------------------------------------------------
# 1. Auto-detect drives by size
# ---------------------------------------------------------------------------
echo "Detecting drives..."
echo ""

# Get all physical drives with their sizes in bytes
declare -A drive_sizes
while IFS= read -r line; do
    dev=$(echo "$line" | awk '{print $1}')
    size=$(echo "$line" | awk '{print $2}')
    drive_sizes["$dev"]="$size"
done < <(lsblk -d -b -o NAME,SIZE | tail -n +2 | grep -v loop)

# Find the OS drive (the one with / mounted)
OS_DEV=$(lsblk -no pkname "$(findmnt -n -o SOURCE /)")

echo "Drives found:"
printf "%-10s %s\n" "DEVICE" "SIZE"
for dev in "${!drive_sizes[@]}"; do
    size_bytes="${drive_sizes[$dev]}"
    size_human=$(lsblk -d -o NAME,SIZE | grep "^$dev" | awk '{print $2}')
    if [[ "$dev" == "$OS_DEV" ]]; then
        printf "%-10s %s  <-- OS drive (will be skipped)\n" "/dev/$dev" "$size_human"
    else
        printf "%-10s %s\n" "/dev/$dev" "$size_human"
    fi
done | sort
echo ""

# Auto-assign roles by size (excluding OS drive)
PLEX_DEV=""
RAID_PRIMARY=""
RAID_SECONDARY=""

# Sort non-OS drives by size descending
while IFS= read -r line; do
    dev=$(echo "$line" | awk '{print $1}')
    size=$(echo "$line" | awk '{print $2}')
    [[ "$dev" == "$OS_DEV" ]] && continue

    size_human=$(lsblk -d -o NAME,SIZE | grep "^$dev" | awk '{print $2}')

    if [[ -z "$PLEX_DEV" ]]; then
        PLEX_DEV="/dev/$dev"
        PLEX_SIZE="$size_human"
    elif [[ -z "$RAID_PRIMARY" ]]; then
        RAID_PRIMARY="/dev/$dev"
        RAID_PRIMARY_SIZE="$size_human"
    elif [[ -z "$RAID_SECONDARY" ]]; then
        RAID_SECONDARY="/dev/$dev"
        RAID_SECONDARY_SIZE="$size_human"
    fi
done < <(lsblk -d -b -o NAME,SIZE | tail -n +2 | grep -v loop | sort -k2 -rn)

echo "Auto-detected drive assignments:"
echo "  plex01  (4TB Plex drive)        -> $PLEX_DEV ($PLEX_SIZE)"
echo "  RAID primary  (new Seagate 1TB) -> $RAID_PRIMARY ($RAID_PRIMARY_SIZE)"
echo "  RAID secondary (old WD 1TB)     -> $RAID_SECONDARY ($RAID_SECONDARY_SIZE)"
echo ""
echo "WARNING: The drives above will be formatted. All data will be lost."
read -rp "Does this look correct? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborted. Edit the script manually to override drive assignments."
    exit 1
fi
echo ""

# ---------------------------------------------------------------------------
# 2. Format and mount plex01
# ---------------------------------------------------------------------------
echo "Formatting $PLEX_DEV as ext4..."
sudo mkfs.ext4 -F "$PLEX_DEV"

PLEX_UUID=$(sudo blkid -s UUID -o value "$PLEX_DEV")
sudo mkdir -p /mnt/plex01

if ! grep -q "/mnt/plex01" /etc/fstab; then
    echo "UUID=$PLEX_UUID   /mnt/plex01   ext4   defaults   0   2" | sudo tee -a /etc/fstab
fi

sudo mount -a
echo "plex01 mounted."
echo ""

# ---------------------------------------------------------------------------
# 3. Create RAID 1 array for personal01
# ---------------------------------------------------------------------------
echo "Creating RAID 1 array from $RAID_PRIMARY (primary) and $RAID_SECONDARY (secondary)..."
sudo mdadm --create /dev/md0 --level=1 --raid-devices=2 "$RAID_PRIMARY" "$RAID_SECONDARY"

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
# 4. Service users and groups
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
# 5. Folder structure and permissions
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

# ---------------------------------------------------------------------------
# 6. Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Phase 2 complete ==="
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
