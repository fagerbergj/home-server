#!/usr/bin/env bats

# Tests for tag_fillers.sh (Plex API version)
# Mocks curl and python3 so no live Plex instance is needed.

SCRIPT="$BATS_TEST_DIRNAME/../tag_fillers.sh"

setup() {
    TMPDIR="$(mktemp -d)"
    FILLER_DIR="$TMPDIR/filler-lists/test-show"
    mkdir -p "$FILLER_DIR" "$TMPDIR/bin" "$TMPDIR/responses"
    export PATH="$TMPDIR/bin:$PATH"
    export PLEX_TOKEN="testtoken"
    export PUT_LOG="$TMPDIR/put_calls.log"
    touch "$PUT_LOG"

    # ---------------------------------------------------------------------------
    # Canned API responses written to files (avoids sed/quoting nightmares)
    # ---------------------------------------------------------------------------

    # /library/search?...type=2
    cat > "$TMPDIR/responses/search.json" <<'JSON'
{"MediaContainer":{"Metadata":[{"ratingKey":"10","title":"Test Show","type":"show"}]}}
JSON

    # /library/metadata/10/children  (seasons)
    cat > "$TMPDIR/responses/seasons.json" <<'JSON'
{"MediaContainer":{"Metadata":[
  {"ratingKey":"20","index":1,"title":"Season 1"},
  {"ratingKey":"21","index":2,"title":"Season 2"}
]}}
JSON

    # /library/metadata/20/children  (season 1 episodes — default)
    cat > "$TMPDIR/responses/season1.json" <<'JSON'
{"MediaContainer":{"Metadata":[
  {"ratingKey":"101","parentIndex":1,"index":1,"title":"Episode One"},
  {"ratingKey":"102","parentIndex":1,"index":2,"title":"Episode Two"},
  {"ratingKey":"103","parentIndex":1,"index":3,"title":"Episode Three"}
]}}
JSON

    # /library/metadata/21/children  (season 2 episodes)
    cat > "$TMPDIR/responses/season2.json" <<'JSON'
{"MediaContainer":{"Metadata":[
  {"ratingKey":"201","parentIndex":2,"index":1,"title":"Episode Four"},
  {"ratingKey":"202","parentIndex":2,"index":2,"title":"Episode Five"}
]}}
JSON

    # Already-tagged variant of season 1 (for untag tests)
    cat > "$TMPDIR/responses/season1_tagged.json" <<'JSON'
{"MediaContainer":{"Metadata":[
  {"ratingKey":"101","parentIndex":1,"index":1,"title":"[Filler] Episode One"},
  {"ratingKey":"102","parentIndex":1,"index":2,"title":"Episode Two"},
  {"ratingKey":"103","parentIndex":1,"index":3,"title":"Episode Three"}
]}}
JSON

    # ---------------------------------------------------------------------------
    # Mock curl: route by URL, log PUTs, read responses from files
    # ---------------------------------------------------------------------------
    cat > "$TMPDIR/bin/curl" <<CURL
#!/bin/bash
method="GET"
url=""
for (( i=1; i<=\$#; i++ )); do
    arg="\${!i}"
    case "\$arg" in
        -X) i=\$(( i+1 )); method="\${!i}" ;;
        http*) url="\$arg" ;;
    esac
done

if [[ "\$method" == "PUT" ]]; then
    echo "\$url" >> "$PUT_LOG"
    exit 0
fi

[[ "\$url" == */library/search*       ]] && cat "$TMPDIR/responses/search.json"  && exit 0
[[ "\$url" == */metadata/10/children* ]] && cat "$TMPDIR/responses/seasons.json" && exit 0
[[ "\$url" == */metadata/20/children* ]] && cat "\${MOCK_S1:-$TMPDIR/responses/season1.json}" && exit 0
[[ "\$url" == */metadata/21/children* ]] && cat "$TMPDIR/responses/season2.json" && exit 0

echo '{"MediaContainer":{"Metadata":[]}}'
CURL
    chmod +x "$TMPDIR/bin/curl"

    # Mock python3 (urlencode): just echo the last argument unchanged
    cat > "$TMPDIR/bin/python3" <<'PY'
#!/bin/bash
echo "${@: -1}"
PY
    chmod +x "$TMPDIR/bin/python3"
}

teardown() {
    rm -rf "$TMPDIR"
}

# Helper: use already-tagged season 1 response
use_tagged_season1() {
    export MOCK_S1="$TMPDIR/responses/season1_tagged.json"
}

# Shorthand: common flags for most tests
flags() { echo "--filler-dir $FILLER_DIR --show Test Show"; }

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

@test "errors if PLEX_TOKEN is missing" {
    echo "1" > "$FILLER_DIR/filler.txt"
    run env -u PLEX_TOKEN bash "$SCRIPT" --filler-dir "$FILLER_DIR" --show "Test Show"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"PLEX_TOKEN"* ]]
}

@test "errors if --show is missing" {
    echo "1" > "$FILLER_DIR/filler.txt"
    run bash "$SCRIPT" --filler-dir "$FILLER_DIR"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"--show is required"* ]]
}

@test "errors if neither filler.txt nor mixedfiller.txt exists" {
    run bash "$SCRIPT" --filler-dir "$FILLER_DIR" --show "Test Show"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"no filler.txt or mixedfiller.txt"* ]]
}

@test "--help prints usage and exits 0" {
    run bash "$SCRIPT" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Usage"* ]]
}

# ---------------------------------------------------------------------------
# Filler range parsing
# ---------------------------------------------------------------------------

@test "loads single episode from filler.txt" {
    echo "1" > "$FILLER_DIR/filler.txt"
    run bash "$SCRIPT" --filler-dir "$FILLER_DIR" --show "Test Show"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Loaded 1 tagged episode"* ]]
}

@test "loads range from filler.txt" {
    echo "1-3" > "$FILLER_DIR/filler.txt"
    run bash "$SCRIPT" --filler-dir "$FILLER_DIR" --show "Test Show"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Loaded 3 tagged episode"* ]]
}

@test "ignores comments in filler.txt" {
    printf "1\n# comment\n2\n" > "$FILLER_DIR/filler.txt"
    run bash "$SCRIPT" --filler-dir "$FILLER_DIR" --show "Test Show"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Loaded 2 tagged episode"* ]]
}

@test "loads from mixedfiller.txt" {
    echo "2" > "$FILLER_DIR/mixedfiller.txt"
    run bash "$SCRIPT" --filler-dir "$FILLER_DIR" --show "Test Show"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"[Mixed Filler]"* ]]
}

@test "show slug is used as default filler dir name" {
    # Script is at scripts/, filler-lists is at ../filler-lists/ relative to scripts/
    # BATS_TEST_DIRNAME is scripts/test/, so ../../filler-lists/ from here
    slug_dir="$BATS_TEST_DIRNAME/../../filler-lists/test-show"
    mkdir -p "$slug_dir"
    echo "1" > "$slug_dir/filler.txt"
    run bash "$SCRIPT" --show "Test Show"
    rm -f "$slug_dir/filler.txt"
    rmdir "$slug_dir" 2>/dev/null || true
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Loaded 1 tagged episode"* ]]
}

# ---------------------------------------------------------------------------
# Episode matching and output
# ---------------------------------------------------------------------------

@test "dry run shows correct season and episode label" {
    echo "1" > "$FILLER_DIR/filler.txt"
    run bash "$SCRIPT" --filler-dir "$FILLER_DIR" --show "Test Show"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"S01E01"* ]]
    [[ "$output" == *"(abs   1)"* ]]
}

@test "dry run shows title transformation" {
    echo "1" > "$FILLER_DIR/filler.txt"
    run bash "$SCRIPT" --filler-dir "$FILLER_DIR" --show "Test Show"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Episode One"* ]]
    [[ "$output" == *"[Filler] Episode One"* ]]
}

@test "absolute numbering carries across seasons" {
    echo "4" > "$FILLER_DIR/filler.txt"   # abs 4 = S02E01
    run bash "$SCRIPT" --filler-dir "$FILLER_DIR" --show "Test Show"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"S02E01"* ]]
    [[ "$output" == *"(abs   4)"* ]]
}

@test "dry run does not PUT to Plex" {
    echo "1" > "$FILLER_DIR/filler.txt"
    run bash "$SCRIPT" --filler-dir "$FILLER_DIR" --show "Test Show"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"DRY RUN"* ]]
    [[ ! -s "$PUT_LOG" ]]
}

@test "dry run reports correct change count" {
    printf "1\n3\n" > "$FILLER_DIR/filler.txt"
    run bash "$SCRIPT" --filler-dir "$FILLER_DIR" --show "Test Show"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"2 episode(s) would be updated"* ]]
}

# ---------------------------------------------------------------------------
# Apply mode
# ---------------------------------------------------------------------------

@test "apply sends PUT to Plex for filler episode" {
    echo "1" > "$FILLER_DIR/filler.txt"
    run bash "$SCRIPT" --apply --filler-dir "$FILLER_DIR" --show "Test Show"
    [[ "$status" -eq 0 ]]
    grep -q "/metadata/101" "$PUT_LOG"
}

@test "apply includes title.locked=1 in PUT" {
    echo "1" > "$FILLER_DIR/filler.txt"
    run bash "$SCRIPT" --apply --filler-dir "$FILLER_DIR" --show "Test Show"
    [[ "$status" -eq 0 ]]
    grep -q "title.locked=1" "$PUT_LOG"
}

@test "apply reports correct change count" {
    printf "1\n2\n" > "$FILLER_DIR/filler.txt"
    run bash "$SCRIPT" --apply --filler-dir "$FILLER_DIR" --show "Test Show"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"2 episode(s) updated"* ]]
}

@test "skips episode already correctly tagged" {
    use_tagged_season1
    echo "1" > "$FILLER_DIR/filler.txt"
    run bash "$SCRIPT" --apply --filler-dir "$FILLER_DIR" --show "Test Show"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"0 episode(s) updated"* ]]
    [[ ! -s "$PUT_LOG" ]]
}

# ---------------------------------------------------------------------------
# Untag mode
# ---------------------------------------------------------------------------

@test "untag dry run shows tag removal" {
    use_tagged_season1
    echo "1" > "$FILLER_DIR/filler.txt"
    run bash "$SCRIPT" --untag --filler-dir "$FILLER_DIR" --show "Test Show"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"[Filler] Episode One"* ]]
    [[ "$output" == *"-> Episode One"* ]]
}

@test "untag apply sends PUT with title.locked=0" {
    use_tagged_season1
    echo "1" > "$FILLER_DIR/filler.txt"
    run bash "$SCRIPT" --apply --untag --filler-dir "$FILLER_DIR" --show "Test Show"
    [[ "$status" -eq 0 ]]
    grep -q "title.locked=0" "$PUT_LOG"
}

@test "untag skips episodes that are not tagged" {
    echo "2" > "$FILLER_DIR/filler.txt"
    run bash "$SCRIPT" --apply --untag --filler-dir "$FILLER_DIR" --show "Test Show"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"0 episode(s) updated"* ]]
}

# ---------------------------------------------------------------------------
# PLEX_URL env var
# ---------------------------------------------------------------------------

@test "PLEX_URL env var overrides the hardcoded default" {
    echo "1" > "$FILLER_DIR/filler.txt"
    run env PLEX_URL=http://plex bash "$SCRIPT" --filler-dir "$FILLER_DIR" --show "Test Show"
    [[ "$status" -eq 0 ]]
}
