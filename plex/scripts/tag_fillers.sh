#!/bin/bash
# Tags episode titles in Plex with [Filler] or [Mixed Filler] as a prefix.
# Updates Plex metadata directly via the Plex API — no files are renamed.
#
# Filler lists live in plex/filler-lists/<show-slug>/ (filler.txt, mixedfiller.txt).
# The show slug is the show name lowercased with spaces replaced by hyphens.
# Override with --filler-dir if needed.
#
# File format (one entry per line, # for comments):
#   28
#   57-71
#   91-112
#
# Usage:
#   tag_fillers.sh [--apply] [--untag] [--filler-dir DIR] --show "Name"
#
# Options:
#   --apply            Actually update Plex (default is dry run)
#   --untag            Remove [Filler] / [Mixed Filler] tags instead of adding
#   --filler-dir DIR   Directory containing filler.txt / mixedfiller.txt
#                      (default: <script-dir>/../filler-lists/<show-slug>)
#   --show NAME        Show title as it appears in Plex
#   --help, -h         Show this help
#
# Environment:
#   PLEX_TOKEN         Plex auth token (required)
#
# Examples:
#   PLEX_TOKEN=$TOKEN tag_fillers.sh --show "Naruto"
#   PLEX_TOKEN=$TOKEN tag_fillers.sh --apply --show "Naruto Shippuden"
#   PLEX_TOKEN=$TOKEN tag_fillers.sh --apply --untag --show "Naruto"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLEX_URL="${PLEX_URL:-https://plex.jasonfagerberg.duckdns.org}"
PLEX_TOKEN="${PLEX_TOKEN:-}"
SHOW_NAME=""
FILLER_DIR=""
DRY_RUN=true
UNTAG=false

for arg in "$@"; do
    case "$arg" in
        --help|-h)
            sed -n '2,/^set /p' "$0" | grep '^#' | sed 's/^# \{0,1\}//'
            exit 0 ;;
    esac
done

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply)       DRY_RUN=false; shift ;;
        --untag)       UNTAG=true; shift ;;
        --show)        SHOW_NAME="$2"; shift 2 ;;
        --filler-dir)  FILLER_DIR="$2"; shift 2 ;;
        --help|-h)     shift ;;
        *)             shift ;;
    esac
done

PLEX_URL="${PLEX_URL%/}"  # strip trailing slash

# Compute filler dir from show name slug if not provided
if [[ -z "$FILLER_DIR" && -n "$SHOW_NAME" ]]; then
    show_slug=$(echo "$SHOW_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
    FILLER_DIR="$SCRIPT_DIR/../filler-lists/$show_slug"
fi

# ---------------------------------------------------------------------------
# Validate
# ---------------------------------------------------------------------------

errors=()
[[ -z "$PLEX_TOKEN" ]]  && errors+=("PLEX_TOKEN env var is required")
[[ -z "$SHOW_NAME" ]]   && errors+=("--show is required")
command -v curl &>/dev/null || errors+=("curl is required")
command -v jq   &>/dev/null || errors+=("jq is required")

if [[ ${#errors[@]} -gt 0 ]]; then
    for e in "${errors[@]}"; do echo "Error: $e"; done
    echo ""
    echo "Usage: $(basename "$0") [--apply] [--untag] --show \"Name\""
    exit 1
fi

echo "=== Show:        $SHOW_NAME"
echo "=== Filler dir:  $FILLER_DIR"
echo "=== Mode:        $( $DRY_RUN && echo 'DRY RUN — pass --apply to update Plex' || echo 'APPLYING CHANGES' )"
$UNTAG && echo "=== Action:      REMOVING tags" || true
echo ""

# ---------------------------------------------------------------------------
# API helpers
# ---------------------------------------------------------------------------

urlencode() {
    python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$1"
}

plex_get() {
    local path="$1"; shift
    local params="${1:-}"
    curl -sf -H "Accept: application/json" \
        "${PLEX_URL}${path}?X-Plex-Token=${PLEX_TOKEN}${params:+&${params}}"
}

plex_put() {
    local path="$1"; shift
    local params="${1:-}"
    curl -sf -X PUT -H "Accept: application/json" \
        "${PLEX_URL}${path}?X-Plex-Token=${PLEX_TOKEN}${params:+&${params}}" > /dev/null
}

# ---------------------------------------------------------------------------
# 1. Parse filler ranges from filler.txt / mixedfiller.txt
# ---------------------------------------------------------------------------

declare -A ep_tags
ep_tag_count=0

load_ranges() {
    local tag="$1" file="$2"
    [[ ! -f "$file" ]] && return
    while IFS= read -r line; do
        line="${line%%#*}"
        line="${line// /}"
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            for (( i=10#${BASH_REMATCH[1]}; i<=10#${BASH_REMATCH[2]}; i++ )); do
                ep_tags[$i]="$tag"
                (( ep_tag_count++ )) || true
            done
        elif [[ "$line" =~ ^[0-9]+$ ]]; then
            ep_tags[$((10#$line))]="$tag"
            (( ep_tag_count++ )) || true
        fi
    done < "$file"
}

load_ranges "[Filler]"       "$FILLER_DIR/filler.txt"
load_ranges "[Mixed Filler]" "$FILLER_DIR/mixedfiller.txt"

if [[ $ep_tag_count -eq 0 ]]; then
    echo "Error: no filler.txt or mixedfiller.txt found in $FILLER_DIR"
    exit 1
fi

echo "Loaded $ep_tag_count tagged episode entries."
echo ""

# ---------------------------------------------------------------------------
# 2. Find the show in Plex
# ---------------------------------------------------------------------------

echo "Searching Plex for: $SHOW_NAME"
encoded_name=$(urlencode "$SHOW_NAME")
search_json=$(plex_get "/library/search" "query=${encoded_name}&type=2")

show_key=$(echo "$search_json" | jq -r --arg name "$SHOW_NAME" '
    .MediaContainer.Metadata // [] |
    (map(select(.title == $name)) + map(select(.title | ascii_downcase | contains($name | ascii_downcase)))) |
    first | .ratingKey // empty
')

if [[ -z "$show_key" ]]; then
    echo "Error: show not found in Plex: $SHOW_NAME"
    echo "Available shows matching that name:"
    echo "$search_json" | jq -r '.MediaContainer.Metadata[]? | "  \(.ratingKey)  \(.title)"'
    exit 1
fi

show_title=$(echo "$search_json" | jq -r --arg key "$show_key" \
    '.MediaContainer.Metadata[] | select(.ratingKey == $key) | .title')
echo "Found: $show_title (key=$show_key)"
echo ""

# ---------------------------------------------------------------------------
# 3. Fetch all seasons (skip specials — season 0)
# ---------------------------------------------------------------------------

seasons_json=$(plex_get "/library/metadata/${show_key}/children")
mapfile -t season_keys < <(echo "$seasons_json" | jq -r '
    .MediaContainer.Metadata[] |
    select(.index > 0) |
    [(.index | tostring), .ratingKey] | join(" ")
' | sort -n | awk '{print $2}')

echo "Found ${#season_keys[@]} season(s)."
echo ""

# ---------------------------------------------------------------------------
# 4. Walk every episode in season order, computing absolute episode number.
#    Update Plex title for any episode in the filler list.
# ---------------------------------------------------------------------------

abs_counter=0
changes=0

for season_key in "${season_keys[@]}"; do
    episodes_json=$(plex_get "/library/metadata/${season_key}/children")

    while IFS=$'\t' read -r ep_key season ep_num title; do
        abs_counter=$(( abs_counter + 1 ))
        abs_ep=$abs_counter
        label=$(printf "S%02dE%02d" "$season" "$ep_num")

        if $UNTAG; then
            # Remove tag only if currently tagged
            if [[ "$title" =~ ^\[(Filler|Mixed\ Filler)\][[:space:]] ]]; then
                new_title="${title#\[Filler\] }"
                new_title="${new_title#\[Mixed Filler\] }"
                printf "  %s  (abs %3d)  %s\n          -> %s\n" "$label" "$abs_ep" "$title" "$new_title"
                if ! $DRY_RUN; then
                    encoded=$(urlencode "$new_title")
                    plex_put "/library/metadata/${ep_key}" "title.value=${encoded}&title.locked=0"
                fi
                (( changes++ )) || true
            fi
        else
            tag="${ep_tags[$abs_ep]:-}"
            [[ -z "$tag" ]] && continue

            # Skip if already correctly tagged
            if [[ "$title" == "$tag "* ]]; then
                continue
            fi

            # Strip any existing tag before applying new one
            clean="${title#\[Filler\] }"
            clean="${clean#\[Mixed Filler\] }"
            new_title="$tag $clean"

            printf "  %s  (abs %3d)  %s\n          -> %s\n" "$label" "$abs_ep" "$title" "$new_title"
            if ! $DRY_RUN; then
                encoded=$(urlencode "$new_title")
                plex_put "/library/metadata/${ep_key}" "title.value=${encoded}&title.locked=1"
            fi
            (( changes++ )) || true
        fi

    done < <(echo "$episodes_json" | jq -r '
        [.MediaContainer.Metadata[] | {ratingKey, parentIndex, index, title}] |
        sort_by(.index) | .[] |
        [.ratingKey, (.parentIndex | tostring), (.index | tostring), .title] |
        join("\t")
    ')
done

echo ""
$DRY_RUN && echo "=== $changes episode(s) would be updated. ===" || echo "=== $changes episode(s) updated. ==="
