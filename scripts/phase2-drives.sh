#!/bin/bash
# Phase 2 — Mount Drives, RAID 1, Users, and Permissions
set -euo pipefail

echo "=== Phase 2: Drive Setup ==="
echo ""

# --- Detect drives ---
echo "Current drives:"
lsblk -f
echo ""

# --- plex01 (4TB) ---
read -rp "Enter device for 4TB Plex drive (e.g. sda): " PLEX_DEV
PLEX_DEV="/dev/$PLEX_DEV"

echo "Formatting $PLEX_DEV as ext4..."
sudo mkfs.ext4 "$PLEX_DEV"

PLEX_UUID=$(sudo blkid -s UUID -o value "$PLEX_DEV")
sudo mkdir -p /mnt/plex01

if ! grep -q "/mnt/plex01" /etc/fstab; then
    echo "UUID=$PLEX_UUID   /mnt/plex01   ext4   defaults   0   2" | sudo tee -a /etc/fstab
fi

sudo mount -a
echo "plex01 mounted at /mnt/plex01"
echo ""

# --- personal01 (RAID 1) ---
echo "Current drives:"
lsblk
echo ""
read -rp "Enter device for NEW 1TB Seagate (RAID primary, e.g. sdb): " RAID_PRIMARY
read -rp "Enter device for OLD 1TB WD (RAID secondary, e.g. sdc): " RAID_SECONDARY

echo "Creating RAID 1 array from /dev/$RAID_PRIMARY and /dev/$RAID_SECONDARY..."
sudo mdadm --create /dev/md0 --level=1 --raid-devices=2 "/dev/$RAID_PRIMARY" "/dev/$RAID_SECONDARY"

echo ""
echo "Waiting for initial RAID sync to complete. This takes ~2 hours."
echo "You can monitor progress with: watch cat /proc/mdstat"
echo "Press ENTER when sync is complete to continue..."
read -r

sudo mkfs.ext4 /dev/md0
sudo mkdir -p /mnt/personal01
sudo mount /dev/md0 /mnt/personal01

sudo mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf
sudo update-initramfs -u

MD0_UUID=$(sudo blkid -s UUID -o value /dev/md0)
if ! grep -q "/mnt/personal01" /etc/fstab; then
    echo "UUID=$MD0_UUID   /mnt/personal01   ext4   defaults   0   2" | sudo tee -a /etc/fstab
fi

echo "personal01 mounted at /mnt/personal01"
echo ""

# --- Service users ---
echo "Creating service users and groups..."

for user in plex immich minecraft qbittorrent; do
    if ! id "$user" &>/dev/null; then
        sudo useradd -r -s /sbin/nologin "$user"
        echo "Created user: $user"
    else
        echo "User $user already exists, skipping"
    fi
done

for group in plex-rw plex-ro personal-rw personal-ro; do
    if ! getent group "$group" &>/dev/null; then
        sudo groupadd "$group"
        echo "Created group: $group"
    else
        echo "Group $group already exists, skipping"
    fi
done

sudo usermod -aG plex-rw qbittorrent
sudo usermod -aG plex-rw jason
sudo usermod -aG plex-ro plex
sudo usermod -aG personal-rw immich
sudo usermod -aG personal-rw jason

echo ""
echo "UIDs and GIDs (update compose files with these):"
id plex
id immich
id minecraft
id qbittorrent
getent group plex-rw
getent group plex-ro
getent group personal-rw

# --- Folder structure and permissions ---
echo ""
echo "Setting up folder structure and permissions..."

sudo apt install -y acl

sudo mkdir -p /mnt/plex01/movies /mnt/plex01/shows
sudo chown -R root:plex-rw /mnt/plex01
sudo chmod -R 2775 /mnt/plex01
sudo setfacl -R -m g:plex-ro:rx /mnt/plex01

sudo mkdir -p /mnt/personal01/photos
sudo chown -R root:personal-rw /mnt/personal01
sudo chmod -R 2775 /mnt/personal01

echo ""
echo "=== Phase 2 complete ==="
echo "Remember to update PUID/PGID in each docker-compose.yml with the UIDs above."
