#!/bin/bash
# Renames a TV show's season folders and episode files into clean Plex-compatible names
# based solely on sort order — no filename parsing required.
#
# Usage:
#   fix_show_naming.sh [--apply] "Show Name" /path/to/show/dir
#
# Examples:
#   fix_show_naming.sh "The Bear" /mnt/ADATASSD/Videos/TV/The\ Bear
#   fix_show_naming.sh --apply "Naruto Shippuden" /mnt/ADATASSD/Videos/TV/Naruto\ Shippuden

set -euo pipefail

VIDEO_EXTS="mkv|mp4|avi|m4v|mov|wmv|flv|webm"

DRY_RUN=true
SHOW_NAME=""
SHOW_DIR=""

for arg in "$@"; do
    case "$arg" in
        --help|-h)
            echo "Usage: $(basename "$0") [--apply] \"Show Name\" /path/to/show/dir"
            echo ""
            echo "Renames season folders and episode files into clean Plex-compatible names"
            echo "based on sort order. Dry run by default — pass --apply to make changes."
            echo ""
            echo "Options:"
            echo "  --apply       Actually rename files and folders (default is dry run)"
            echo "  --help, -h    Show this help"
            echo ""
            echo "Examples:"
            echo "  $(basename "$0") \"The Bear\" \"/mnt/ADATASSD/Videos/TV/The Bear\""
            echo "  $(basename "$0") --apply \"The Bear\" \"/mnt/ADATASSD/Videos/TV/The Bear\""
            exit 0 ;;
        --apply) DRY_RUN=false ;;
        *) [[ -z "$SHOW_NAME" ]] && SHOW_NAME="$arg" || SHOW_DIR="$arg" ;;
    esac
done

if [[ -z "$SHOW_NAME" || -z "$SHOW_DIR" ]]; then
    echo "Usage: $(basename "$0") [--apply] \"Show Name\" /path/to/show/dir"
    echo "Run with --help for more info."
    exit 1
fi

if [[ ! -d "$SHOW_DIR" ]]; then
    echo "Error: directory not found: $SHOW_DIR"
    exit 1
fi

run() {
    if $DRY_RUN; then
        echo "  [dry-run] $*"
    else
        "$@"
    fi
}

echo "=== Show:  $SHOW_NAME"
echo "=== Path:  $SHOW_DIR"
echo "=== Mode:  $( $DRY_RUN && echo 'DRY RUN — pass --apply to make changes' || echo 'APPLYING CHANGES' )"
echo ""

# Collect season dirs: any subdirectory, sorted naturally
mapfile -t season_dirs < <(find "$SHOW_DIR" -mindepth 1 -maxdepth 1 -type d | sort -V)

if [[ ${#season_dirs[@]} -eq 0 ]]; then
    echo "No subdirectories found in $SHOW_DIR"
    exit 1
fi

season_index=0

for season_dir in "${season_dirs[@]}"; do
    season_index=$(( season_index + 1 ))
    folder_name=$(basename "$season_dir")
    new_folder_name=$(printf "Season %02d" "$season_index")
    new_season_dir="$SHOW_DIR/$new_folder_name"

    echo "--- $folder_name -> $new_folder_name ---"

    # Collect video files, sorted naturally
    mapfile -t files < <(find "$season_dir" -maxdepth 1 -type f | grep -iE "\.($VIDEO_EXTS)$" | sort -V)

    if [[ ${#files[@]} -eq 0 ]]; then
        echo "  (no video files found)"
    fi

    ep_index=0
    for file in "${files[@]}"; do
        ep_index=$(( ep_index + 1 ))
        filename=$(basename "$file")
        ext="${filename##*.}"
        new_name=$(printf "%s - S%02dE%03d.%s" "$SHOW_NAME" "$season_index" "$ep_index" "${ext,,}")
        if [[ "$filename" != "$new_name" ]]; then
            echo "  $filename"
            echo "    -> $new_name"
            run mv "$file" "$season_dir/$new_name"
        fi
    done

    # Rename season folder (do after files so paths stay valid)
    if [[ "$folder_name" != "$new_folder_name" ]]; then
        run mv "$season_dir" "$new_season_dir"
    fi

    echo ""
done

echo "=== Done ==="
