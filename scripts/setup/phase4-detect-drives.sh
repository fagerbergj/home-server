#!/bin/bash
# Detects HDDs, buckets by size, resolves to stable /dev/disk/by-id/ata-*
# paths, and writes drives.json describing the two ZFS pools the next
# script (phase4-drives.sh) will create.
#
# Detection rules — match the hardware documented in hardware_upgrades.md:
#   media_pool    (RAIDZ2):  4 HDDs in the 24-28 TB range  (Seagate Exos 26TB)
#   personal_pool (mirror):  2 HDDs in the 7-9 TB range    (Dell J7W80 8TB)
#
# Environment overrides:
#   DRYRUN=1   — print the detected assignments; do not write drives.json.
#
# After running, review drives.json by hand before invoking phase4-drives.sh.
set -euo pipefail

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUTPUT="$SCRIPT_DIR/drives.json"
DRYRUN="${DRYRUN:-0}"

MEDIA_MIN_GB=$((24 * 1000))
MEDIA_MAX_GB=$((28 * 1000))
PERSONAL_MIN_GB=$((7 * 1000))
PERSONAL_MAX_GB=$((9 * 1000))
EXPECTED_MEDIA=4
EXPECTED_PERSONAL=2

echo "=== Phase 4: Drive Detection ==="
echo ""

# ---------------------------------------------------------------------------
# Enumerate HDDs, skipping the OS drive
# ---------------------------------------------------------------------------

OS_DEV=$(lsblk -no pkname "$(findmnt -n -o SOURCE /)")

# lsblk gives us: name size-bytes type
#   TYPE=disk filters out partitions and loops.
MEDIA_DEVICES=()
PERSONAL_DEVICES=()
OTHER_DEVICES=()

while IFS= read -r line; do
    dev=$(awk '{print $1}' <<<"$line")
    size_b=$(awk '{print $2}' <<<"$line")
    type=$(awk '{print $3}' <<<"$line")

    [[ "$type" != "disk" ]] && continue
    [[ "$dev" == "$OS_DEV" ]] && continue

    # Size in GB (base-10) — matches how disk manufacturers advertise.
    size_gb=$((size_b / 1000 / 1000 / 1000))

    if (( size_gb >= MEDIA_MIN_GB && size_gb <= MEDIA_MAX_GB )); then
        MEDIA_DEVICES+=("$dev:$size_gb")
    elif (( size_gb >= PERSONAL_MIN_GB && size_gb <= PERSONAL_MAX_GB )); then
        PERSONAL_DEVICES+=("$dev:$size_gb")
    else
        OTHER_DEVICES+=("$dev:$size_gb")
    fi
done < <(lsblk -d -b -n -o NAME,SIZE,TYPE)

# ---------------------------------------------------------------------------
# Resolve /dev/sdX → /dev/disk/by-id/ata-*
# ---------------------------------------------------------------------------

# Prefer ata-* over wwn-*: human-readable (model + serial) and stable.
by_id_for() {
    local dev="$1"
    local link target found=""
    for link in /dev/disk/by-id/ata-*; do
        [[ -e "$link" ]] || continue
        target=$(readlink -f "$link")
        if [[ "$target" == "/dev/$dev" ]]; then
            # Skip -partN symlinks, we want the whole-disk one.
            [[ "$link" == *-part* ]] && continue
            found="$link"
            break
        fi
    done
    echo "$found"
}

resolve_devices() {
    local -n src="$1"
    local -n dest="$2"
    local entry dev size_gb by_id
    for entry in "${src[@]}"; do
        dev="${entry%:*}"
        size_gb="${entry#*:}"
        by_id=$(by_id_for "$dev")
        if [[ -z "$by_id" ]]; then
            echo "Warning: no /dev/disk/by-id/ata-* symlink for /dev/$dev — using /dev/$dev" >&2
            by_id="/dev/$dev"
        fi
        dest+=("$by_id:$size_gb")
    done
}

MEDIA_RESOLVED=()
PERSONAL_RESOLVED=()
resolve_devices MEDIA_DEVICES MEDIA_RESOLVED
resolve_devices PERSONAL_DEVICES PERSONAL_RESOLVED

# ---------------------------------------------------------------------------
# Print summary
# ---------------------------------------------------------------------------

printf "OS drive (excluded):  /dev/%s\n" "$OS_DEV"
echo ""
printf "media_pool candidates (%d found, expected %d):\n" \
    "${#MEDIA_RESOLVED[@]}" "$EXPECTED_MEDIA"
for entry in "${MEDIA_RESOLVED[@]:-}"; do
    [[ -z "$entry" ]] && continue
    printf "  %s  (%s GB)\n" "${entry%:*}" "${entry#*:}"
done
echo ""
printf "personal_pool candidates (%d found, expected %d):\n" \
    "${#PERSONAL_RESOLVED[@]}" "$EXPECTED_PERSONAL"
for entry in "${PERSONAL_RESOLVED[@]:-}"; do
    [[ -z "$entry" ]] && continue
    printf "  %s  (%s GB)\n" "${entry%:*}" "${entry#*:}"
done
echo ""
if (( ${#OTHER_DEVICES[@]} > 0 )); then
    echo "Unassigned drives (neither size bucket matched):"
    for entry in "${OTHER_DEVICES[@]}"; do
        printf "  /dev/%s  (%s GB)\n" "${entry%:*}" "${entry#*:}"
    done
    echo ""
fi

# ---------------------------------------------------------------------------
# Write drives.json — still emit even if counts don't match, so the user
# can hand-edit it. The phase4-drives.sh consumer will preflight-check
# before creating any pools.
# ---------------------------------------------------------------------------

emit_json_array() {
    local -n arr="$1"
    local entry first=1
    printf '[\n'
    for entry in "${arr[@]:-}"; do
        [[ -z "$entry" ]] && continue
        if (( first )); then
            first=0
        else
            printf ',\n'
        fi
        printf '      "%s"' "${entry%:*}"
    done
    printf '\n    ]'
}

if [[ "$DRYRUN" == "1" ]]; then
    echo "DRYRUN=1 — skipping drives.json write."
else
    {
        printf '{\n'
        printf '  "media_pool": {\n'
        printf '    "layout": "raidz2",\n'
        printf '    "devices": '
        emit_json_array MEDIA_RESOLVED
        printf '\n  },\n'
        printf '  "personal_pool": {\n'
        printf '    "layout": "mirror",\n'
        printf '    "devices": '
        emit_json_array PERSONAL_RESOLVED
        printf '\n  }\n'
        printf '}\n'
    } > "$OUTPUT"
    echo "Written to $OUTPUT"
fi

# ---------------------------------------------------------------------------
# Exit with a non-zero status if the detected counts are wrong, so CI or
# careless re-runs notice. The file is still on disk for manual fixup.
# ---------------------------------------------------------------------------

status=0
if (( ${#MEDIA_RESOLVED[@]} != EXPECTED_MEDIA )); then
    echo "ERROR: expected $EXPECTED_MEDIA media_pool drives, found ${#MEDIA_RESOLVED[@]}." >&2
    status=1
fi
if (( ${#PERSONAL_RESOLVED[@]} != EXPECTED_PERSONAL )); then
    echo "ERROR: expected $EXPECTED_PERSONAL personal_pool drives, found ${#PERSONAL_RESOLVED[@]}." >&2
    status=1
fi

if (( status == 0 )); then
    echo ""
    echo "Review the config — then run:"
    echo "  scripts/setup/phase4-drives.sh"
else
    echo ""
    echo "Hand-edit $OUTPUT to correct the device list before running phase4-drives.sh." >&2
fi
exit "$status"
