#!/usr/bin/env bats

# Tests for phase4-ids.sh
# Mocks id and getent — safe to run on any machine

SCRIPT="$BATS_TEST_DIRNAME/../phase4-ids.sh"

setup() {
    export TMPDIR="$(mktemp -d)"
    export PATH="$TMPDIR/bin:$PATH"

    mkdir -p "$TMPDIR/bin"

    cat > "$TMPDIR/bin/id" <<'EOF'
#!/bin/bash
case "$2" in
    plex)        echo "1001" ;;
    immich)      echo "1002" ;;
    qbittorrent) echo "1004" ;;
    *)           echo "1000" ;;
esac
EOF
    chmod +x "$TMPDIR/bin/id"

    cat > "$TMPDIR/bin/getent" <<'EOF'
#!/bin/bash
case "$2" in
    plex-ro)     echo "plex-ro:x:2002:" ;;
    plex-rw)     echo "plex-rw:x:2001:" ;;
    personal-rw) echo "personal-rw:x:2003:" ;;
    *)           return 1 ;;
esac
EOF
    chmod +x "$TMPDIR/bin/getent"

    # Copy compose files to temp dir so we don't touch the real ones
    export REPO_ROOT="$TMPDIR/repo"
    mkdir -p "$REPO_ROOT/plex" "$REPO_ROOT/photos" "$REPO_ROOT/qbittorrent"

    cat > "$REPO_ROOT/plex/docker-compose.yml" <<'EOF'
      - PUID=<plex-uid>    # run: id plex
      - PGID=<plex-ro-gid> # run: getent group plex-ro
EOF

    cat > "$REPO_ROOT/photos/docker-compose.yml" <<'EOF'
      - PUID=<immich-uid>         # run: id immich
      - PGID=<personal-rw-gid>    # run: getent group personal-rw
EOF

    cat > "$REPO_ROOT/qbittorrent/docker-compose.yml" <<'EOF'
      - PUID=<qbittorrent-uid>  # run: id qbittorrent
      - PGID=<plex-rw-gid>      # run: getent group plex-rw
EOF
}

teardown() {
    rm -rf "$TMPDIR"
}

@test "updates plex PUID" {
    REPO_ROOT="$REPO_ROOT" run bash "$SCRIPT"
    grep -q "PUID=1001" "$REPO_ROOT/plex/docker-compose.yml"
}

@test "updates plex PGID" {
    REPO_ROOT="$REPO_ROOT" run bash "$SCRIPT"
    grep -q "PGID=2002" "$REPO_ROOT/plex/docker-compose.yml"
}

@test "updates immich PUID" {
    REPO_ROOT="$REPO_ROOT" run bash "$SCRIPT"
    grep -q "PUID=1002" "$REPO_ROOT/photos/docker-compose.yml"
}

@test "updates immich PGID" {
    REPO_ROOT="$REPO_ROOT" run bash "$SCRIPT"
    grep -q "PGID=2003" "$REPO_ROOT/photos/docker-compose.yml"
}

@test "updates qbittorrent PUID" {
    REPO_ROOT="$REPO_ROOT" run bash "$SCRIPT"
    grep -q "PUID=1004" "$REPO_ROOT/qbittorrent/docker-compose.yml"
}

@test "updates qbittorrent PGID" {
    REPO_ROOT="$REPO_ROOT" run bash "$SCRIPT"
    grep -q "PGID=2001" "$REPO_ROOT/qbittorrent/docker-compose.yml"
}

@test "prints all UIDs and GIDs" {
    REPO_ROOT="$REPO_ROOT" run bash "$SCRIPT"
    [[ "$output" == *"plex uid"*"1001"* ]]
    [[ "$output" == *"immich uid"*"1002"* ]]
    [[ "$output" == *"qbittorrent uid"*"1004"* ]]
    [[ "$output" == *"plex-ro gid"*"2002"* ]]
    [[ "$output" == *"plex-rw gid"*"2001"* ]]
    [[ "$output" == *"personal-rw gid"*"2003"* ]]
}

@test "prints done on completion" {
    REPO_ROOT="$REPO_ROOT" run bash "$SCRIPT"
    [[ "$output" == *"done"* ]]
}
