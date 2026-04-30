#!/bin/bash
# Bulk imports an anime season/series into Sonarr by matching absolute episode numbers
# in filenames to TVDB episode data via the Sonarr API. Uses Sonarr's own quality and
# language detection — only the episode mapping is corrected.
#
# Usage:
#   sonarr_import.sh [--apply] [--url URL] --api-key KEY (--series "Name" | --series-id ID) /path/to/folder
#
# Options:
#   --apply          Actually import (default is dry run)
#   --api-key KEY    Sonarr API key (Settings > General > Security)
#   --url URL        Sonarr base URL (default: http://localhost:8989)
#   --series NAME    Series name to search for in Sonarr (picks first match)
#   --series-id ID   Sonarr series ID (avoids ambiguous name matches)
#
# Examples:
#   sonarr_import.sh --api-key abc123 --series "Naruto" /mnt/media/downloads/Naruto
#   sonarr_import.sh --apply --api-key abc123 --series-id 26 /mnt/media/downloads/Naruto

set -euo pipefail

SONARR_URL="http://localhost:8989"
API_KEY=""
SERIES_NAME=""
SERIES_ID=""
FOLDER=""
DRY_RUN=true

usage() {
    echo "Usage: $(basename "$0") [--apply] [--url URL] --api-key KEY (--series \"Name\" | --series-id ID) /path/to/folder"
    echo "Run with --help for full usage."
}

for arg in "$@"; do
    case "$arg" in
        --help|-h)
            sed -n '2,/^set /p' "$0" | grep '^#' | sed 's/^# \{0,1\}//'
            exit 0 ;;
    esac
done

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply)        DRY_RUN=false; shift ;;
        --url)          SONARR_URL="$2"; shift 2 ;;
        --api-key)      API_KEY="$2"; shift 2 ;;
        --series)       SERIES_NAME="$2"; shift 2 ;;
        --series-id)    SERIES_ID="$2"; shift 2 ;;
        --help|-h)      shift ;;
        *)              FOLDER="$1"; shift ;;
    esac
done

# ---------------------------------------------------------------------------
# Validate
# ---------------------------------------------------------------------------

errors=()
[[ -z "$API_KEY" ]]                          && errors+=("--api-key is required")
[[ -z "$SERIES_NAME" && -z "$SERIES_ID" ]]   && errors+=("--series or --series-id is required")
[[ -z "$FOLDER" ]]      && errors+=("folder path is required")
[[ -n "$FOLDER" && ! -d "$FOLDER" ]] && errors+=("folder not found: $FOLDER")
command -v curl &>/dev/null || errors+=("curl is required")
command -v jq   &>/dev/null || errors+=("jq is required (sudo apt install -y jq)")

if [[ ${#errors[@]} -gt 0 ]]; then
    for e in "${errors[@]}"; do echo "Error: $e"; done
    echo ""; usage
    exit 1
fi

# ---------------------------------------------------------------------------
# API helpers
# ---------------------------------------------------------------------------

api_get() {
    local endpoint="$1"; shift
    curl -sf -G -H "X-Api-Key: $API_KEY" "$@" "$SONARR_URL/api/v3/$endpoint"
}

api_post() {
    curl -sf -X POST \
        -H "X-Api-Key: $API_KEY" \
        -H "Content-Type: application/json" \
        -d "$2" \
        "$SONARR_URL/api/v3/$1"
}

# ---------------------------------------------------------------------------
# 1. Find series
# ---------------------------------------------------------------------------

echo "=== Folder: $FOLDER"
echo "=== Mode:   $($DRY_RUN && echo 'DRY RUN — pass --apply to import' || echo 'IMPORTING')"
echo ""

if [[ -n "$SERIES_ID" ]]; then
    echo "Looking up series id=$SERIES_ID in Sonarr..."
    series_json=$(api_get "series/$SERIES_ID")
    SERIES_TITLE=$(echo "$series_json" | jq -r '.title')
    if [[ "$SERIES_TITLE" == "null" || -z "$SERIES_TITLE" ]]; then
        echo "Error: no series found with id=$SERIES_ID"
        exit 1
    fi
    echo "Found: $SERIES_TITLE (id=$SERIES_ID)"
else
    echo "Looking up series: $SERIES_NAME"
    series_json=$(api_get "series" | jq --arg name "$SERIES_NAME" \
        '[.[] | select(.title | ascii_downcase | contains($name | ascii_downcase))]')
    count=$(echo "$series_json" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
        echo "Error: no series found matching '$SERIES_NAME'"
        echo "Check that the series is added to Sonarr first."
        exit 1
    fi

    if [[ "$count" -gt 1 ]]; then
        echo "Multiple matches — use --series-id to pick one:"
        echo "$series_json" | jq -r '.[] | "  \(.id)  \(.title)"'
        echo ""
    fi

    SERIES_ID=$(echo "$series_json" | jq '.[0].id')
    SERIES_TITLE=$(echo "$series_json" | jq -r '.[0].title')
    echo "Found: $SERIES_TITLE (id=$SERIES_ID)"
fi
echo ""

# ---------------------------------------------------------------------------
# 2. Build absolute episode number -> episode ID map
# ---------------------------------------------------------------------------

echo "Fetching episode list from Sonarr..."
episodes_json=$(api_get "episode" --data-urlencode "seriesId=$SERIES_ID")
ep_count=$(echo "$episodes_json" | jq '[.[] | select(.absoluteEpisodeNumber != null)] | length')

if [[ "$ep_count" -eq 0 ]]; then
    echo "Warning: no episodes with absolute episode numbers found."
    echo "Sonarr may not have absolute numbering data for this series."
    echo "Try setting Series Type to Anime in Sonarr first."
    exit 1
fi

echo "Found $ep_count episodes with absolute numbering."

# Build a JSON object: {"1": {id: 123, season: 1, episode: 1}, ...}
mapping_json=$(echo "$episodes_json" | jq '
    [.[] | select(.absoluteEpisodeNumber != null) | {
        key: (.absoluteEpisodeNumber | tostring),
        value: {id: .id, season: .seasonNumber, episode: .episodeNumber}
    }] | from_entries
')

# ---------------------------------------------------------------------------
# 3. Ask Sonarr to analyze the folder (scan root + all subdirectories)
#    The manualimport endpoint does not recurse, so we call it once per dir.
# ---------------------------------------------------------------------------

echo "Scanning folder with Sonarr..."
manualimport_json="[]"

scan_folder() {
    local dir="$1"
    local result
    # Do NOT pass seriesId here — Sonarr ignores folder and scans the series'
    # media root instead, which may not exist yet. We correct the mapping in the POST.
    result=$(api_get "manualimport" \
        --data-urlencode "folder=$dir" \
        --data-urlencode "filterExistingFiles=false")
    manualimport_json=$(echo "$manualimport_json $result" | jq -s '(.[0] + .[1]) | unique_by(.path)')

    # Recurse into subdirectories
    while IFS= read -r subdir; do
        scan_folder "$subdir"
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d | sort -V)
}

scan_folder "$FOLDER"

file_count=$(echo "$manualimport_json" | jq 'length')
echo "Found $file_count video file(s) in folder."
echo ""

# ---------------------------------------------------------------------------
# 4. Match each file to the correct episode via absolute number
# ---------------------------------------------------------------------------

matched=0
skipped=0
import_files_json="[]"

while IFS= read -r file_obj; do
    path=$(echo "$file_obj" | jq -r '.path')
    filename=$(basename "$path")

    # Extract absolute episode number from filename patterns:
    #   " - NNN - "  (e.g. "[Anime Time] Naruto - 001 - Title.mkv")
    #   " - NNN."    (e.g. "Show - 001.mkv")
    #   "Episode NNN" (e.g. "Naruto Shippuden Episode 001 Title.mkv")
    if [[ "$filename" =~ [[:space:]]-[[:space:]]([0-9]+)[[:space:]]-[[:space:]] ]] || \
       [[ "$filename" =~ [[:space:]]-[[:space:]]([0-9]+)\. ]] || \
       [[ "$filename" =~ [Ee]pisode[[:space:]]+([0-9]+) ]]; then
        abs_raw="${BASH_REMATCH[1]}"
        abs_num=$(( 10#$abs_raw ))   # strip leading zeros
    else
        echo "  SKIP (no episode number in filename): $filename"
        (( skipped++ )) || true
        continue
    fi

    ep_info=$(echo "$mapping_json" | jq --arg n "$abs_num" '.[$n] // empty')
    if [[ -z "$ep_info" ]]; then
        echo "  SKIP (abs ep $abs_num not in Sonarr episode list): $filename"
        (( skipped++ )) || true
        continue
    fi

    ep_id=$(echo "$ep_info" | jq '.id')
    season=$(echo "$ep_info" | jq '.season')
    episode=$(echo "$ep_info" | jq '.episode')
    label=$(printf "S%02dE%02d" "$season" "$episode")

    echo "  $label  (abs $abs_raw)  $filename"

    # Minimal fields only — extra fields from the GET response (rejections, etc.)
    # can cause Sonarr to re-run title validation and block the import
    corrected=$(echo "$file_obj" | jq \
        --argjson seriesId "$SERIES_ID" \
        --argjson epId "$ep_id" \
        '{path, seriesId: $seriesId, episodeIds: [$epId], quality, languages, releaseGroup: (.releaseGroup // "")}')

    import_files_json=$(echo "$import_files_json" | jq --argjson obj "$corrected" '. + [$obj]')
    (( matched++ )) || true

done < <(echo "$manualimport_json" | jq -c '.[]')

echo ""
echo "Matched: $matched file(s)"
[[ $skipped -gt 0 ]] && echo "Skipped: $skipped file(s)"
echo ""

if [[ $matched -eq 0 ]]; then
    echo "Nothing to import."
    exit 0
fi

if $DRY_RUN; then
    echo "Dry run complete. Pass --apply to import."
    exit 0
fi

# ---------------------------------------------------------------------------
# 5. POST directly to /api/v3/manualimport
#    The /command endpoint has enum deserialization issues with importMode.
#    The direct endpoint accepts the files array with per-file importMode.
# ---------------------------------------------------------------------------

# Write payload to a temp file — 220+ file JSON is too large for a shell argument
tmp_payload=$(mktemp /tmp/sonarr_import_XXXXXX.json)
trap 'rm -f "$tmp_payload"' EXIT

# importMode: 0=Auto — Sonarr hardlinks the file (same filesystem) then deletes the source.
# Requires plex-rw group write permission on the source directory so Sonarr can delete.
# Fix existing dirs: sudo chmod -R g+w /mnt/media/downloads/
echo "$import_files_json" | jq \
    '{"name": "ManualImport", "files": ., "importMode": 0}' > "$tmp_payload"

echo "Sending import to Sonarr..."
result=$(curl -s -X POST \
    -H "X-Api-Key: $API_KEY" \
    -H "Content-Type: application/json" \
    --data "@$tmp_payload" \
    "$SONARR_URL/api/v3/command")

if echo "$result" | jq -e '.id' &>/dev/null; then
    command_id=$(echo "$result" | jq '.id')
    echo "Command queued (id=$command_id)."
    echo "Check Sonarr's Activity > History tab for results."
else
    echo "Error response from Sonarr:"
    echo "$result" | jq '.' 2>/dev/null || echo "$result"
    exit 1
fi
