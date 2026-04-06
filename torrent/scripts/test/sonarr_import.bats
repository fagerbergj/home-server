#!/usr/bin/env bats

# Tests for sonarr_import.sh
# Mocks curl so no live Sonarr instance is needed.

SCRIPT="$BATS_TEST_DIRNAME/../sonarr_import.sh"

# ---------------------------------------------------------------------------
# Shared mock data
# ---------------------------------------------------------------------------

SERIES_JSON='{"id": 26, "title": "Naruto"}'

# 5 episodes with absolute numbering
EPISODES_JSON='[
  {"id": 101, "absoluteEpisodeNumber": 1,  "seasonNumber": 1, "episodeNumber": 1},
  {"id": 102, "absoluteEpisodeNumber": 2,  "seasonNumber": 1, "episodeNumber": 2},
  {"id": 103, "absoluteEpisodeNumber": 3,  "seasonNumber": 1, "episodeNumber": 3},
  {"id": 104, "absoluteEpisodeNumber": 4,  "seasonNumber": 1, "episodeNumber": 4},
  {"id": 105, "absoluteEpisodeNumber": 5,  "seasonNumber": 1, "episodeNumber": 5}
]'

COMMAND_RESPONSE='{"id": 999}'

setup() {
    TMPDIR="$(mktemp -d)"
    FOLDER="$TMPDIR/downloads"
    mkdir -p "$FOLDER"

    mkdir -p "$TMPDIR/bin"
    export PATH="$TMPDIR/bin:$PATH"

    # Mock curl: inspect the URL (last non-flag argument) and return canned data.
    # POST to /command returns the command queued response.
    # GET to /series/ID returns series JSON.
    # GET to /episode returns episode list.
    # GET to /manualimport reads MOCK_MANUALIMPORT_JSON env var (set per-test).
    cat > "$TMPDIR/bin/curl" <<'CURL'
#!/bin/bash
method="GET"
url=""
for (( i=1; i<=$#; i++ )); do
    arg="${!i}"
    case "$arg" in
        -X) i=$(( i+1 )); method="${!i}" ;;
        http*) url="$arg" ;;
    esac
done

if [[ "$method" == "POST" && "$url" == */command ]]; then
    echo '{"id": 999}'
    exit 0
fi

if [[ "$url" == */series/26 ]]; then
    echo '{"id": 26, "title": "Naruto"}'
    exit 0
fi

if [[ "$url" == */series ]]; then
    echo '[{"id": 26, "title": "Naruto"}]'
    exit 0
fi

if [[ "$url" == */episode* ]]; then
    echo '[
      {"id": 101, "absoluteEpisodeNumber": 1,  "seasonNumber": 1, "episodeNumber": 1},
      {"id": 102, "absoluteEpisodeNumber": 2,  "seasonNumber": 1, "episodeNumber": 2},
      {"id": 103, "absoluteEpisodeNumber": 3,  "seasonNumber": 1, "episodeNumber": 3},
      {"id": 104, "absoluteEpisodeNumber": 4,  "seasonNumber": 1, "episodeNumber": 4},
      {"id": 105, "absoluteEpisodeNumber": 5,  "seasonNumber": 1, "episodeNumber": 5}
    ]'
    exit 0
fi

if [[ "$url" == */manualimport* ]]; then
    echo "${MOCK_MANUALIMPORT_JSON:-[]}"
    exit 0
fi

echo "[]"
CURL
    chmod +x "$TMPDIR/bin/curl"
}

teardown() {
    rm -rf "$TMPDIR"
}

# Build a manualimport GET response entry for a given file path.
manualimport_entry() {
    local path="$1"
    printf '{"path": "%s", "quality": {"quality": {"id": 1}, "revision": {"version": 1}}, "languages": [{"id": 1}], "releaseGroup": ""}' "$path"
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

@test "shows usage when no args given" {
    run bash "$SCRIPT"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Usage"* ]]
}

@test "errors if --api-key is missing" {
    run bash "$SCRIPT" --series-id 26 "$FOLDER"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"--api-key is required"* ]]
}

@test "errors if neither --series nor --series-id is given" {
    run bash "$SCRIPT" --api-key testkey "$FOLDER"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"--series or --series-id is required"* ]]
}

@test "errors if folder path is missing" {
    run bash "$SCRIPT" --api-key testkey --series-id 26
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"folder path is required"* ]]
}

@test "errors if folder does not exist" {
    run bash "$SCRIPT" --api-key testkey --series-id 26 /nonexistent/path
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"folder not found"* ]]
}

@test "--help prints usage and exits 0" {
    run bash "$SCRIPT" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Usage"* ]]
}

# ---------------------------------------------------------------------------
# Series lookup
# ---------------------------------------------------------------------------

@test "resolves series by name" {
    run bash "$SCRIPT" --api-key testkey --series "Naruto" "$FOLDER"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Found: Naruto"* ]]
}

@test "resolves series by id" {
    run bash "$SCRIPT" --api-key testkey --series-id 26 "$FOLDER"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Found: Naruto (id=26)"* ]]
}

# ---------------------------------------------------------------------------
# Episode number extraction — dry run
# ---------------------------------------------------------------------------

@test "matches dash-number-dash pattern" {
    f="$FOLDER/[Anime Time] Naruto - 001 - Enter Naruto Uzumaki!.mkv"
    touch "$f"
    export MOCK_MANUALIMPORT_JSON="[$(manualimport_entry "$f")]"

    run bash "$SCRIPT" --api-key testkey --series-id 26 "$FOLDER"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"S01E01  (abs 001)"* ]]
    [[ "$output" == *"Matched: 1"* ]]
}

@test "matches dash-number-dot pattern (no title)" {
    f="$FOLDER/Naruto - 002.mkv"
    touch "$f"
    export MOCK_MANUALIMPORT_JSON="[$(manualimport_entry "$f")]"

    run bash "$SCRIPT" --api-key testkey --series-id 26 "$FOLDER"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"S01E02  (abs 002)"* ]]
    [[ "$output" == *"Matched: 1"* ]]
}

@test "matches Episode NNN pattern" {
    f="$FOLDER/Naruto Shippuden Episode 003 Title.mkv"
    touch "$f"
    export MOCK_MANUALIMPORT_JSON="[$(manualimport_entry "$f")]"

    run bash "$SCRIPT" --api-key testkey --series-id 26 "$FOLDER"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"S01E03  (abs 003)"* ]]
    [[ "$output" == *"Matched: 1"* ]]
}

@test "skips files with no recognizable episode number" {
    f="$FOLDER/some.random.file.mkv"
    touch "$f"
    export MOCK_MANUALIMPORT_JSON="[$(manualimport_entry "$f")]"

    run bash "$SCRIPT" --api-key testkey --series-id 26 "$FOLDER"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"SKIP (no episode number in filename)"* ]]
    [[ "$output" == *"Matched: 0"* ]]
}

@test "skips files whose absolute number is not in Sonarr episode list" {
    f="$FOLDER/Naruto - 999 - Way Out of Range.mkv"
    touch "$f"
    export MOCK_MANUALIMPORT_JSON="[$(manualimport_entry "$f")]"

    run bash "$SCRIPT" --api-key testkey --series-id 26 "$FOLDER"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"SKIP (abs ep 999 not in Sonarr episode list)"* ]]
    [[ "$output" == *"Matched: 0"* ]]
}

@test "strips leading zeros when matching episode number" {
    f="$FOLDER/Naruto - 005 - The Fifth Episode.mkv"
    touch "$f"
    export MOCK_MANUALIMPORT_JSON="[$(manualimport_entry "$f")]"

    run bash "$SCRIPT" --api-key testkey --series-id 26 "$FOLDER"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"S01E05  (abs 005)"* ]]
    [[ "$output" == *"Matched: 1"* ]]
}

@test "matches multiple files and deduplicates" {
    f1="$FOLDER/Naruto - 001 - First.mkv"
    f2="$FOLDER/Naruto - 002 - Second.mkv"
    touch "$f1" "$f2"
    export MOCK_MANUALIMPORT_JSON="[$(manualimport_entry "$f1"), $(manualimport_entry "$f2")]"

    run bash "$SCRIPT" --api-key testkey --series-id 26 "$FOLDER"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Matched: 2"* ]]
}

# ---------------------------------------------------------------------------
# Dry run vs apply
# ---------------------------------------------------------------------------

@test "dry run does not POST to Sonarr" {
    f="$FOLDER/Naruto - 001 - Title.mkv"
    touch "$f"
    export MOCK_MANUALIMPORT_JSON="[$(manualimport_entry "$f")]"

    # Inject a curl that fails loudly if a POST is attempted
    cat > "$TMPDIR/bin/curl" <<'CURL'
#!/bin/bash
for arg in "$@"; do
    case "$arg" in
        -X) shift; [[ "$1" == "POST" ]] && { echo "ERROR: POST called in dry run" >&2; exit 1; } ;;
    esac
done
# GET fallbacks
for arg in "$@"; do
    [[ "$arg" == */series/26 ]]   && echo '{"id": 26, "title": "Naruto"}' && exit 0
    [[ "$arg" == */episode* ]]    && echo '[{"id":101,"absoluteEpisodeNumber":1,"seasonNumber":1,"episodeNumber":1}]' && exit 0
    [[ "$arg" == */manualimport* ]] && echo "${MOCK_MANUALIMPORT_JSON:-[]}" && exit 0
done
echo "[]"
CURL
    chmod +x "$TMPDIR/bin/curl"

    run bash "$SCRIPT" --api-key testkey --series-id 26 "$FOLDER"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Dry run complete"* ]]
    [[ "$output" != *"ERROR: POST"* ]]
}

@test "apply sends command to Sonarr and reports queued id" {
    f="$FOLDER/Naruto - 001 - Title.mkv"
    touch "$f"
    export MOCK_MANUALIMPORT_JSON="[$(manualimport_entry "$f")]"

    run bash "$SCRIPT" --apply --api-key testkey --series-id 26 "$FOLDER"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Command queued (id=999)"* ]]
}

@test "nothing to import exits cleanly with no POST" {
    export MOCK_MANUALIMPORT_JSON="[]"

    run bash "$SCRIPT" --apply --api-key testkey --series-id 26 "$FOLDER"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Nothing to import"* ]]
}
