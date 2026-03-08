#!/bin/bash
# Tags Naruto Shippuden filler episodes in Plex by prepending [Filler] or [Mixed Filler]
# to the episode title and locking the field so Plex won't re-scrape it.
#
# Usage:
#   plex_tag_fillers.sh [--apply] [--untag] /path/to/show/dir

set -euo pipefail

PLEX_URL="http://127.0.0.1:32400"
PLEX_TOKEN="h_Bkg9wfMEnr4LVGVvsY"
SHOW_RATING_KEY="1623"

DRY_RUN=true
UNTAG=false
SHOW_DIR=""

for arg in "$@"; do
    case "$arg" in
        --apply) DRY_RUN=false ;;
        --untag) UNTAG=true ;;
        --help|-h)
            echo "Usage: $(basename "$0") [--apply] [--untag] /path/to/show/dir"
            echo "Dry run by default — pass --apply to make changes."
            exit 0 ;;
        *) SHOW_DIR="$arg" ;;
    esac
done

if [[ -z "$SHOW_DIR" || ! -d "$SHOW_DIR" ]]; then
    echo "Usage: $(basename "$0") [--apply] [--untag] /path/to/show/dir"
    exit 1
fi

echo "=== Plex Filler Tagger ==="
echo "=== Mode: $( $DRY_RUN && echo 'DRY RUN — pass --apply to make changes' || echo 'APPLYING CHANGES' )"
$UNTAG && echo "=== Action: REMOVING tags"
echo ""

# ---------------------------------------------------------------------------
# 1. Parse filler ranges
# ---------------------------------------------------------------------------
declare -A ep_tags

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
            done
        elif [[ "$line" =~ ^[0-9]+$ ]]; then
            ep_tags[$((10#$line))]="$tag"
        fi
    done < "$file"
}

load_ranges "[Filler]"       "$SHOW_DIR/filler.txt"
load_ranges "[Mixed Filler]" "$SHOW_DIR/mixedfiller.txt"

echo "Loaded ${#ep_tags[@]} tagged episode entries."
echo ""

# ---------------------------------------------------------------------------
# 2. Fetch seasons and build absolute episode offset map
#    season_start[season_index] = first absolute ep number of that season
# ---------------------------------------------------------------------------
declare -A season_start

seasons_xml=$(curl -sf "$PLEX_URL/library/metadata/$SHOW_RATING_KEY/children?X-Plex-Token=$PLEX_TOKEN")

abs_offset=0
while IFS= read -r season_line; do
    s_index=$(echo "$season_line" | grep -oP '\bindex="\K[0-9]+' | head -1)
    leaf_count=$(echo "$season_line" | grep -oP 'leafCount="\K[0-9]+' | head -1)
    [[ -z "$s_index" || -z "$leaf_count" ]] && continue
    season_start[$s_index]=$(( abs_offset + 1 ))
    abs_offset=$(( abs_offset + leaf_count ))
done < <(echo "$seasons_xml" | grep -oP '<Directory[^>]+>' | grep 'type="season"')

echo "Built season offsets for ${#season_start[@]} season(s)."
echo ""

# ---------------------------------------------------------------------------
# 3. Process all episodes
# ---------------------------------------------------------------------------
changes=0

season_keys=$(echo "$seasons_xml" | grep -oP '<Directory[^>]+>' | grep 'type="season"' | grep -oP 'ratingKey="\K[0-9]+')

for season_key in $season_keys; do
    eps_xml=$(curl -sf "$PLEX_URL/library/metadata/$season_key/children?X-Plex-Token=$PLEX_TOKEN")

    while IFS= read -r ep_line; do
        rating_key=$(echo "$ep_line" | grep -oP 'ratingKey="\K[0-9]+' | head -1)
        ep_index=$(echo "$ep_line"   | grep -oP '\bindex="\K[0-9]+'   | head -1)
        s_index=$(echo "$ep_line"    | grep -oP 'parentIndex="\K[0-9]+' | head -1)
        title=$(echo "$ep_line"      | grep -oP 'title="\K[^"]+' | head -1)

        [[ -z "$rating_key" || -z "$ep_index" || -z "$s_index" || -z "$title" ]] && continue

        # Decode HTML entities in title
        title=$(echo "$title" | sed 's/&#39;/'"'"'/g; s/&amp;/\&/g; s/&quot;/"/g')

        if [[ -z "${season_start[$s_index]+_}" ]]; then
            echo "  WARNING: no offset for season $s_index, skipping ep $ep_index"
            continue
        fi

        abs_ep=$(( season_start[$s_index] + ep_index - 1 ))

        if $UNTAG; then
            new_title=$(echo "$title" | sed -E 's/^\[(Filler|Mixed Filler)\] //')
            [[ "$title" == "$new_title" ]] && continue
        else
            tag="${ep_tags[$abs_ep]:-}"
            [[ -z "$tag" ]] && continue
            [[ "$title" == "$tag "* ]] && continue
            clean_title=$(echo "$title" | sed -E 's/^\[(Filler|Mixed Filler)\] //')
            new_title="$tag $clean_title"
        fi

        printf "  ep %3d (S%02dE%02d, key %s): %s\n               -> %s\n" \
            "$abs_ep" "$s_index" "$ep_index" "$rating_key" "$title" "$new_title"

        if ! $DRY_RUN; then
            encoded_title=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$new_title")
            curl -sf -X PUT \
                "$PLEX_URL/library/metadata/$rating_key?title=$encoded_title&title.locked=1&X-Plex-Token=$PLEX_TOKEN" \
                > /dev/null
        fi

        (( changes++ )) || true
    done < <(echo "$eps_xml" | grep -oP '<Video[^>]+>')
done

echo ""
echo "=== $changes episode(s) $( $DRY_RUN && echo 'would be' || echo '' ) updated. ==="
