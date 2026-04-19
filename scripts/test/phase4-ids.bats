#!/usr/bin/env bats
# Tests for scripts/setup/phase4-ids.sh

load 'test_helper.bash'

SRC_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../setup" && pwd)/phase4-ids.sh"

setup() {
    TEST_DIR="$(mktemp -d)"
    export TEST_DIR
    stub_bin_init
    make_getent_stub
    make_id_stub
    seed_default_users_and_groups

    REPO_ROOT="$TEST_DIR/repo"
    mkdir -p "$REPO_ROOT/plex" "$REPO_ROOT/photos" "$REPO_ROOT/torrent" \
             "$REPO_ROOT/scripts/setup"

    # Representative compose snippets — only the lines the script patches
    # plus a little surrounding context. Uses arbitrary starting PUID/PGID
    # values to prove the replacement is idempotent across states.
    cat > "$REPO_ROOT/plex/docker-compose.yml" <<'EOF'
services:
  plex:
    environment:
      - PUID=1    # run: id plex
      - PGID=1 # run: getent group plex-ro
EOF

    cat > "$REPO_ROOT/photos/docker-compose.yml" <<'EOF'
services:
  immich-server:
    environment:
      - PUID=2         # run: id immich
      - PGID=2    # run: getent group personal-rw
EOF

    cat > "$REPO_ROOT/torrent/docker-compose.yml" <<'EOF'
services:
  qbittorrent:
    environment:
      - PUID=3  # run: id qbittorrent
      - PGID=3      # run: getent group plex-rw
  sonarr:
    environment:
      - PUID=3  # run: id sonarr
      - PGID=3 # run: getent group plex-rw
  radarr:
    environment:
      - PUID=3  # run: id radarr
      - PGID=3 # run: getent group plex-rw
EOF

    SCRIPT="$REPO_ROOT/scripts/setup/phase4-ids.sh"
    cp "$SRC_SCRIPT" "$SCRIPT"
    chmod +x "$SCRIPT"
    export REPO_ROOT
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

@test "fails before patching if a required user is missing" {
    # Drop `plex` from the fixture getent db.
    sed -i '/^passwd|plex|/d' "$TEST_DIR/getent.db"
    run "$SCRIPT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"user 'plex' does not exist"* ]]
    # File contents must be unchanged.
    grep -q 'PUID=1' "$REPO_ROOT/plex/docker-compose.yml"
}

@test "fails before patching if a required group is missing" {
    sed -i '/^group|plex-ro|/d' "$TEST_DIR/getent.db"
    run "$SCRIPT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"group 'plex-ro' does not exist"* ]]
    grep -q 'PGID=1' "$REPO_ROOT/plex/docker-compose.yml"
}

@test "fails if a compose file is missing" {
    rm "$REPO_ROOT/photos/docker-compose.yml"
    run "$SCRIPT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"compose file not found"* ]]
    [[ "$output" == *"photos/docker-compose.yml"* ]]
}

# ---------------------------------------------------------------------------
# Happy path — patching
# ---------------------------------------------------------------------------

@test "patches plex PUID/PGID" {
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -q 'PUID=999 *# run: id plex'                   "$REPO_ROOT/plex/docker-compose.yml"
    grep -q 'PGID=1002 *# run: getent group plex-ro'     "$REPO_ROOT/plex/docker-compose.yml"
}

@test "patches immich PUID/PGID" {
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -q 'PUID=996 *# run: id immich'                     "$REPO_ROOT/photos/docker-compose.yml"
    grep -q 'PGID=1003 *# run: getent group personal-rw'     "$REPO_ROOT/photos/docker-compose.yml"
}

@test "patches qbittorrent/sonarr/radarr PUIDs" {
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -q 'PUID=994 *# run: id qbittorrent' "$REPO_ROOT/torrent/docker-compose.yml"
    grep -q 'PUID=988 *# run: id sonarr'      "$REPO_ROOT/torrent/docker-compose.yml"
    grep -q 'PUID=987 *# run: id radarr'      "$REPO_ROOT/torrent/docker-compose.yml"
}

@test "patches all three plex-rw PGID lines" {
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    local count
    count=$(grep -c 'PGID=1001 *# run: getent group plex-rw' "$REPO_ROOT/torrent/docker-compose.yml")
    [ "$count" -eq 3 ]
}

@test "is idempotent — re-running produces the same file" {
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    local snapshot_plex snapshot_torrent
    snapshot_plex=$(cat "$REPO_ROOT/plex/docker-compose.yml")
    snapshot_torrent=$(cat "$REPO_ROOT/torrent/docker-compose.yml")
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$snapshot_plex" = "$(cat "$REPO_ROOT/plex/docker-compose.yml")" ]
    [ "$snapshot_torrent" = "$(cat "$REPO_ROOT/torrent/docker-compose.yml")" ]
}
