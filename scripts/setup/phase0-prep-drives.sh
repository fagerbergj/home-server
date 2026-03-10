#!/bin/bash
# Phase 0 — Prepare drives with GPT partition tables
set -euo pipefail

echo "=== Phase 0: Drive Preparation ==="
echo ""

# Find the OS drive
OS_DEV=$(lsblk -no pkname "$(findmnt -n -o SOURCE /)")

echo "Scanning drives..."
echo ""

DRIVES_TO_PREP=()

while IFS= read -r line; do
    dev=$(echo "$line" | awk '{print $1}')
    size_human=$(lsblk -d -o NAME,SIZE | grep "^$dev" | awk '{print $2}')

    if [[ "$dev" == "$OS_DEV" ]]; then
        printf "%-10s %s  <-- OS drive (skipping)\n" "/dev/$dev" "$size_human"
        continue
    fi

    # Check if drive already has a partition table
    part_table=$(sudo parted "/dev/$dev" print 2>&1 | grep "Partition Table:" | awk '{print $3}' || true)

    if [[ "$part_table" == "unknown" || -z "$part_table" ]]; then
        printf "%-10s %s  <-- no partition table, will prep\n" "/dev/$dev" "$size_human"
        DRIVES_TO_PREP+=("$dev")
    else
        printf "%-10s %s  <-- already has partition table ($part_table), skipping\n" "/dev/$dev" "$size_human"
    fi
done < <(lsblk -d -b -o NAME,SIZE | tail -n +2 | grep -v loop | sort -k2 -rn)

echo ""

if [[ ${#DRIVES_TO_PREP[@]} -eq 0 ]]; then
    echo "All non-OS drives already have partition tables. Nothing to do."
    exit 0
fi

echo "Drives to prep: ${DRIVES_TO_PREP[*]}"
echo "WARNING: This will create a new GPT partition table on each drive listed above."
read -rp "Continue? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborted."
    exit 1
fi
echo ""

for dev in "${DRIVES_TO_PREP[@]}"; do
    echo "Prepping /dev/$dev..."
    sudo parted -s "/dev/$dev" mklabel gpt
    sudo parted -s -a optimal "/dev/$dev" mkpart primary ext4 0% 100%
    echo "  /dev/${dev}1 created."
done

echo ""
echo "=== Phase 0 complete ==="
echo "Run phase4-drives.sh to format and mount drives."
