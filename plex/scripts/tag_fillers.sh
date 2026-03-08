#!/bin/bash
# Tags episode files with [Filler] or [Mixed Filler] as a prefix to the episode title.
#
# Looks for these files in the show directory:
#   filler.txt       — episode numbers/ranges to tag as [Filler]
#   mixedfiller.txt  — episode numbers/ranges to tag as [Mixed Filler]
#
# File format (one entry per line, # for comments):
#   28
#   57-71
#   91-112
#
# Episode number extraction (in order of preference):
#   1. "Episode NNN" in filename  (e.g. "Show Episode 028 Title.mkv")
#   2. SxxExx + season offset     (e.g. "Show - S02E005.mkv" with S02 starting at ep 33)
#   3. Sort order fallback
#
# Result:
#   Show - S01E028 - Homecoming.mkv     ->  Show - S01E028 - [Filler] Homecoming.mkv
#   Show - S01E028.mkv                  ->  Show - S01E028 - [Filler].mkv
#   Show Episode 028 Homecoming.mkv     ->  Show Episode 028 [Filler] Homecoming.mkv
#
# Usage:
#   tag_fillers.sh [--apply] [--untag] /path/to/show/dir

set -euo pipefail

VIDEO_EXTS="mkv|mp4|avi|m4v|mov|wmv|flv|webm"
DRY_RUN=true
UNTAG=false
SHOW_DIR=""

for arg in "$@"; do
    case "$arg" in
        --help|-h)
            echo "Usage: $(basename "$0") [--apply] [--untag] /path/to/show/dir"
            echo ""
            echo "Tags episode files with [Filler] or [Mixed Filler] as a prefix to the"
            echo "episode title, based on filler.txt / mixedfiller.txt in the show directory."
            echo "Dry run by default — pass --apply to make changes."
            echo ""
            echo "Options:"
            echo "  --apply       Actually rename files (default is dry run)"
            echo "  --untag       Remove [Filler] / [Mixed Filler] tags instead of adding them"
            echo "  --help, -h    Show this help"
            echo ""
            echo "Filler list format (one entry per line in filler.txt / mixedfiller.txt):"
            echo "  28"
            echo "  57-71"
            echo "  91-112"
            echo ""
            echo "Examples:"
            echo "  $(basename "$0") \"/mnt/ADATASSD/Videos/TV/Naruto Shippuden\""
            echo "  $(basename "$0") --apply \"/mnt/ADATASSD/Videos/TV/Naruto Shippuden\""
            echo "  $(basename "$0") --apply --untag \"/mnt/ADATASSD/Videos/TV/Naruto Shippuden\""
            exit 0 ;;
        --apply) DRY_RUN=false ;;
        --untag) UNTAG=true ;;
        *) SHOW_DIR="$arg" ;;
    esac
done

if [[ -z "$SHOW_DIR" || ! -d "$SHOW_DIR" ]]; then
    echo "Usage: $(basename "$0") [--apply] [--untag] /path/to/show/dir"
    echo "Run with --help for more info."
    exit 1
fi

run() { $DRY_RUN && echo "    [dry-run] mv \"$1\" -> \"$(basename "$2")\"" || mv "$1" "$2"; }

echo "=== Path:   $SHOW_DIR"
echo "=== Mode:   $( $DRY_RUN && echo 'DRY RUN — pass --apply to make changes' || echo 'APPLYING CHANGES' )"
$UNTAG && echo "=== Action: REMOVING tags"
echo ""

# ---------------------------------------------------------------------------
# 1. Parse episode ranges from a file into ep_tags[]
# ---------------------------------------------------------------------------
declare -A ep_tags

load_ranges() {
    local tag="$1" file="$2"
    [[ ! -f "$file" ]] && return
    while IFS= read -r line; do
        line="${line%%#*}"   # strip comments
        line="${line// /}"   # strip spaces
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

if [[ ${#ep_tags[@]} -eq 0 ]]; then
    echo "Error: no filler.txt or mixedfiller.txt found in $SHOW_DIR"
    exit 1
fi

echo "Loaded ${#ep_tags[@]} tagged episode entries."
echo ""

# ---------------------------------------------------------------------------
# 2. Scan season dirs — build sort-order list and season->start_ep map
# ---------------------------------------------------------------------------
declare -A season_start  # season_start[N] = first absolute ep number of season N
declare -a all_files     # 1-based list of all episode files in order
all_files+=("")          # placeholder so index 1 = episode 1

abs_counter=0
season_index=0
mapfile -t season_dirs < <(find "$SHOW_DIR" -mindepth 1 -maxdepth 1 -type d | sort -V)

for season_dir in "${season_dirs[@]}"; do
    season_index=$(( season_index + 1 ))
    season_start[$season_index]=$(( abs_counter + 1 ))
    mapfile -t sfiles < <(find "$season_dir" -maxdepth 1 -type f \
        | grep -iE "\.($VIDEO_EXTS)$" | sort -V)
    for f in "${sfiles[@]}"; do
        abs_counter=$(( abs_counter + 1 ))
        all_files+=("$f")
    done
done

echo "Found $abs_counter episode files across $season_index season(s)."
echo ""

# ---------------------------------------------------------------------------
# 3. Get absolute episode number for a file
# ---------------------------------------------------------------------------
get_abs_ep() {
    local file="$1" sort_idx="$2"
    local base
    base=$(basename "$file")
    # Strip existing tags for clean parsing
    base=$(echo "$base" | sed -E 's/ - \[(Filler|Mixed Filler)\]( |$)/ /g; s/\[(Filler|Mixed Filler)\] //g')

    # "Episode NNN"
    if [[ "$base" =~ [Ee]pisode[[:space:]]+([0-9]+) ]]; then
        echo $(( 10#${BASH_REMATCH[1]} )); return
    fi

    # "SxxExx" + season offset
    if [[ "$base" =~ [Ss]([0-9]+)[Ee]([0-9]+) ]]; then
        local s=$(( 10#${BASH_REMATCH[1]} ))
        local e=$(( 10#${BASH_REMATCH[2]} ))
        if [[ -n "${season_start[$s]+_}" ]]; then
            echo $(( season_start[$s] + e - 1 )); return
        fi
    fi

    echo "$sort_idx"
}

# ---------------------------------------------------------------------------
# 4. Build new filename with tag as prefix to episode title
# ---------------------------------------------------------------------------
apply_tag() {
    local filename="$1" tag="$2"
    local ext="${filename##*.}"
    local base="${filename%.$ext}"

    # Strip existing tag
    base=$(echo "$base" | sed -E 's/ - \[(Filler|Mixed Filler)\]( (.+))?$/\3/; s/^ - //')
    base=$(echo "$base" | sed -E 's/[[:space:]]?\[(Filler|Mixed Filler)\][[:space:]]?/ /g')
    base="${base%% }"; base="${base## }"

    # "Show - SxxExx - Title"
    if [[ "$base" =~ ^(.*[Ss][0-9]+[Ee][0-9]+)[[:space:]]*-[[:space:]]*(.+)$ ]]; then
        echo "${BASH_REMATCH[1]} - $tag ${BASH_REMATCH[2]}.$ext"
    # "Show - SxxExx" (no title)
    elif [[ "$base" =~ ^(.*[Ss][0-9]+[Ee][0-9]+)[[:space:]]*$ ]]; then
        echo "${BASH_REMATCH[1]} - $tag.$ext"
    # "Show Episode NNN Title"
    elif [[ "$base" =~ ^(.*[Ee]pisode[[:space:]]+[0-9]+)[[:space:]]+(.+)$ ]]; then
        echo "${BASH_REMATCH[1]} $tag ${BASH_REMATCH[2]}.$ext"
    # "Show Episode NNN" (no title)
    elif [[ "$base" =~ ^(.*[Ee]pisode[[:space:]]+[0-9]+)[[:space:]]*$ ]]; then
        echo "${BASH_REMATCH[1]} $tag.$ext"
    else
        echo "$base - $tag.$ext"
    fi
}

remove_tag() {
    local filename="$1"
    local ext="${filename##*.}"
    local base="${filename%.$ext}"
    base=$(echo "$base" | sed -E 's/ - \[(Filler|Mixed Filler)\]( (.+))?$/\3/; s/^ - //')
    base=$(echo "$base" | sed -E 's/[[:space:]]?\[(Filler|Mixed Filler)\][[:space:]]?/ /g')
    base="${base%% }"; base="${base## }"
    echo "$base.$ext"
}

# ---------------------------------------------------------------------------
# 5. Process all files
# ---------------------------------------------------------------------------
changes=0

for (( idx=1; idx<=abs_counter; idx++ )); do
    file="${all_files[$idx]}"
    dir=$(dirname "$file")
    filename=$(basename "$file")

    abs_ep=$(get_abs_ep "$file" "$idx")

    if $UNTAG; then
        new_name=$(remove_tag "$filename")
    else
        tag="${ep_tags[$abs_ep]:-}"
        [[ -z "$tag" ]] && continue
        new_name=$(apply_tag "$filename" "$tag")
    fi

    if [[ "$filename" != "$new_name" ]]; then
        printf "  ep %3d: %s\n          -> %s\n" "$abs_ep" "$filename" "$new_name"
        run "$file" "$dir/$new_name"
        (( changes++ )) || true
    fi
done

echo ""
echo "=== $changes file(s) $( $DRY_RUN && echo 'would be' || echo '' ) renamed. ==="
