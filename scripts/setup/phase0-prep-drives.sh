#!/bin/bash
# Phase 0 — Wipe non-OS drives so phase4-drives.sh can claim them whole-disk
# for ZFS.
#
# `zpool create` will refuse a disk that already carries a filesystem, RAID,
# or partition signature unless you pass -f. Force-overriding is fine on a
# clean build but masks "wait, I plugged in the wrong disk" mistakes — so the
# safer default is to make the operator wipe explicitly here, then let phase4
# create pools without -f.
#
# On brand-new drives this is a no-op. On recertified drives or drives moved
# from a previous server it removes the leftover ext4/mdraid/zfs labels.
set -euo pipefail

echo "=== Phase 0: Drive Wipe ==="
echo ""

OS_DEV=$(lsblk -no pkname "$(findmnt -n -o SOURCE /)")

DRIVES_TO_WIPE=()

while IFS= read -r line; do
    dev=$(echo "$line" | awk '{print $1}')
    size_human=$(lsblk -d -o NAME,SIZE | grep "^$dev " | awk '{print $2}')

    if [[ "$dev" == "$OS_DEV" ]]; then
        printf "%-10s %s  <-- OS drive (skipping)\n" "/dev/$dev" "$size_human"
        continue
    fi

    sigs=$(sudo wipefs -n "/dev/$dev" 2>/dev/null | wc -l)
    if (( sigs > 0 )); then
        printf "%-10s %s  <-- has %d signature(s), will wipe\n" "/dev/$dev" "$size_human" "$sigs"
        DRIVES_TO_WIPE+=("$dev")
    else
        printf "%-10s %s  <-- already clean, skipping\n" "/dev/$dev" "$size_human"
    fi
done < <(lsblk -d -b -o NAME,SIZE | tail -n +2 | grep -v loop | sort -k2 -rn)

echo ""

if (( ${#DRIVES_TO_WIPE[@]} == 0 )); then
    echo "All non-OS drives are already clean. Nothing to do."
    exit 0
fi

echo "Drives to wipe: ${DRIVES_TO_WIPE[*]}"
echo "WARNING: this destroys filesystem/RAID signatures on each drive listed above."
read -rp "Continue? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborted."
    exit 1
fi
echo ""

for dev in "${DRIVES_TO_WIPE[@]}"; do
    echo "Wiping /dev/$dev..."
    sudo wipefs -a "/dev/$dev"
    # Belt-and-braces: sgdisk zaps both primary and backup GPT headers.
    sudo sgdisk --zap-all "/dev/$dev" >/dev/null
done

echo ""
echo "=== Phase 0 complete ==="
echo "Run scripts/setup/phase4-detect-drives.sh next."
