#!/bin/bash
# Detects connected drives, assigns roles, and writes drives.json.
# Review and edit drives.json before running phase4-drives.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="$SCRIPT_DIR/drives.json"

echo "=== Phase 4: Drive Detection ==="
echo ""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

part_dev() {
    local dev="$1"
    if [[ "$dev" == *nvme* ]]; then
        echo "${dev}p1"
    else
        echo "${dev}1"
    fi
}

has_filesystem() {
    local part="$1"
    local fs
    fs=$(blkid -s TYPE -o value "$part" 2>/dev/null || true)
    [[ -n "$fs" ]]
}

# ---------------------------------------------------------------------------
# Detect drives
# ---------------------------------------------------------------------------

OS_DEV=$(lsblk -no pkname "$(findmnt -n -o SOURCE /)")

DRIVES=()
while IFS= read -r line; do
    dev=$(echo "$line" | awk '{print $1}')
    [[ "$dev" == "$OS_DEV" ]] && continue
    DRIVES+=("$dev")
done < <(lsblk -d -b -o NAME,SIZE | tail -n +2 | grep -v loop | sort -k2 -rn)

if [[ ${#DRIVES[@]} -lt 3 ]]; then
    echo "Error: expected at least 3 non-OS drives (plex01, raid primary, raid secondary), found ${#DRIVES[@]}."
    exit 1
fi

PLEX01_DEV=$(part_dev "${DRIVES[0]}")
RAID_PRIMARY_DEV=$(part_dev "${DRIVES[1]}")
RAID_SECONDARY_DEV=$(part_dev "${DRIVES[2]}")
PLEX02_DEV=""
if [[ ${#DRIVES[@]} -ge 4 ]]; then
    PLEX02_DEV=$(part_dev "${DRIVES[3]}")
fi

# ---------------------------------------------------------------------------
# Check for existing filesystems → suggest preserve
# ---------------------------------------------------------------------------

PLEX01_PRESERVE=false
if has_filesystem "/dev/$PLEX01_DEV"; then
    PLEX01_PRESERVE=true
fi

PLEX02_PRESERVE=false
if [[ -n "$PLEX02_DEV" ]] && has_filesystem "/dev/$PLEX02_DEV"; then
    PLEX02_PRESERVE=true
fi

# ---------------------------------------------------------------------------
# Print summary
# ---------------------------------------------------------------------------

size_of() { lsblk -d -o NAME,SIZE | awk -v d="$1" '$1==d {print $2}'; }

echo "Detected assignments (OS drive /dev/$OS_DEV excluded):"
echo ""
printf "  %-16s %-12s %-12s %s\n" "role" "device" "size" "preserve"
printf "  %-16s %-12s %-12s %s\n" "----" "------" "----" "--------"
printf "  %-16s %-12s %-12s %s\n" "plex01" "/dev/$PLEX01_DEV" "$(size_of "${DRIVES[0]}")" "$PLEX01_PRESERVE"
printf "  %-16s %-12s %-12s %s\n" "raid primary" "/dev/$RAID_PRIMARY_DEV" "$(size_of "${DRIVES[1]}")" "n/a"
printf "  %-16s %-12s %-12s %s\n" "raid secondary" "/dev/$RAID_SECONDARY_DEV" "$(size_of "${DRIVES[2]}")" "n/a"
if [[ -n "$PLEX02_DEV" ]]; then
    printf "  %-16s %-12s %-12s %s\n" "plex02" "/dev/$PLEX02_DEV" "$(size_of "${DRIVES[3]}")" "$PLEX02_PRESERVE"
fi
echo ""

# ---------------------------------------------------------------------------
# Write drives.json
# ---------------------------------------------------------------------------

if [[ -n "$PLEX02_DEV" ]]; then
    cat > "$OUTPUT" <<EOF
{
  "plex01": {
    "device": "/dev/$PLEX01_DEV",
    "preserve": $PLEX01_PRESERVE
  },
  "plex02": {
    "device": "/dev/$PLEX02_DEV",
    "preserve": $PLEX02_PRESERVE
  },
  "personal01": {
    "raid_primary": "/dev/$RAID_PRIMARY_DEV",
    "raid_secondary": "/dev/$RAID_SECONDARY_DEV"
  }
}
EOF
else
    cat > "$OUTPUT" <<EOF
{
  "plex01": {
    "device": "/dev/$PLEX01_DEV",
    "preserve": $PLEX01_PRESERVE
  },
  "personal01": {
    "raid_primary": "/dev/$RAID_PRIMARY_DEV",
    "raid_secondary": "/dev/$RAID_SECONDARY_DEV"
  }
}
EOF
fi

echo "Written to $OUTPUT"
echo ""
echo "Review the config — especially 'preserve' flags — then run:"
echo "  scripts/setup/phase4-drives.sh"
