#!/bin/bash
# Move audiobook files from a flat source folder into a pre-created destination,
# stripping the common filename prefix in the process.
#
# Usage:
#   ./format.sh <source> <dest>           # dry run
#   ./format.sh <source> <dest> --apply   # apply
#
# Example:
#   ./format.sh "Andy Weir - Project Hail Mary" "Andy Weir/Project Hail Mary"
#
#   Andy Weir - Project Hail Mary - 01.mp3  →  Andy Weir/Project Hail Mary/01.mp3

set -euo pipefail

SOURCE="${1:-}"
DEST="${2:-}"
APPLY=false
if [[ "${3:-}" == "--apply" ]]; then
    APPLY=true
fi

if [[ -z "$SOURCE" || -z "$DEST" ]]; then
    echo "Usage: $0 <source> <dest> [--apply]"
    exit 1
fi

if [[ ! -d "$SOURCE" ]]; then
    echo "Error: source '$SOURCE' is not a directory"
    exit 1
fi

if [[ ! -d "$DEST" ]]; then
    echo "Error: dest '$DEST' does not exist — create it first"
    exit 1
fi

# ---------------------------------------------------------------------------
# Detect prefix from source folder name
# ---------------------------------------------------------------------------

mapfile -t files < <(find "$SOURCE" -maxdepth 1 -type f | sort)

if [[ ${#files[@]} -eq 0 ]]; then
    echo "No files found in '$SOURCE'"
    exit 1
fi

# Files are named "FolderName - TrackInfo.ext" — use folder name as prefix
folder="$(basename "$SOURCE")"
prefix="$folder - "

echo "Source:  $SOURCE"
echo "Dest:    $DEST"
echo "Prefix to strip: '$prefix'"
[[ "$APPLY" == false ]] && echo "(dry run — pass --apply to apply)"
echo ""

# ---------------------------------------------------------------------------
# Move and rename
# ---------------------------------------------------------------------------

CHANGES=0
for f in "${files[@]}"; do
    base="$(basename "$f")"
    new_base="${base#"$prefix"}"

    # Strip leading spaces/dashes left after prefix removal
    new_base="$(echo "$new_base" | sed 's/^[[:space:]-]*//')"

    if [[ -z "$new_base" ]]; then
        echo "  SKIP (empty name after strip): $base"
        continue
    fi

    echo "  $base  →  $new_base"

    if [[ "$APPLY" == true ]]; then
        mv "$f" "$DEST/$new_base"
    fi

    CHANGES=$((CHANGES + 1))
done

echo ""
if [[ "$APPLY" == false ]]; then
    echo "$CHANGES file(s) would be moved. Run with --apply to apply."
else
    echo "$CHANGES file(s) moved."
fi
