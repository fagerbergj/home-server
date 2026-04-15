#!/usr/bin/env bats
# Tests for scripts/check-active-users.sh
#
# Stubs docker, curl, and ss so nothing touches a real server.

setup() {
    TEST_DIR="$(mktemp -d)"
    STUB_BIN="$TEST_DIR/bin"
    mkdir -p "$STUB_BIN"

    # Copy script under test and patch nothing — stubs handle isolation
    SCRIPT="$TEST_DIR/check-active-users.sh"
    cp "$(dirname "$BATS_TEST_FILENAME")/../check-active-users.sh" "$SCRIPT"
    chmod +x "$SCRIPT"

    # Default stubs (no active users, all containers running)

    cat > "$STUB_BIN/docker" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"ps"* ]]; then
    echo "minecraft"
fi
if [[ "$*" == *"rcon-cli list"* ]]; then
    echo "0 of a max 10 players online."
fi
EOF
    chmod +x "$STUB_BIN/docker"

    cat > "$STUB_BIN/curl" <<'EOF'
#!/usr/bin/env bash
# Default: 0 Plex sessions
echo '<MediaContainer size="0"></MediaContainer>'
EOF
    chmod +x "$STUB_BIN/curl"

    cat > "$STUB_BIN/ss" <<'EOF'
#!/usr/bin/env bash
# Default: no established connections
echo "Netid State  Recv-Q Send-Q Local Address:Port Peer Address:Port"
EOF
    chmod +x "$STUB_BIN/ss"

    export PATH="$STUB_BIN:$PATH"
    export TEST_DIR SCRIPT
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ── All clear ─────────────────────────────────────────────────────────────

@test "exits 0 when no active users on any service" {
    run bash "$SCRIPT" <<< ""
    [ "$status" -eq 0 ]
}

@test "prints all clear message when no active users" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"All clear"* ]]
}

# ── Minecraft ─────────────────────────────────────────────────────────────

@test "detects active Minecraft players" {
    cat > "$STUB_BIN/docker" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"ps"* ]]; then
    echo "minecraft"
fi
if [[ "$*" == *"rcon-cli list"* ]]; then
    echo "2 of a max 10 players online: Alice, Bob"
fi
EOF
    chmod +x "$STUB_BIN/docker"

    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ACTIVE USERS DETECTED"* ]]
}

@test "prints Minecraft player count in output" {
    cat > "$STUB_BIN/docker" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"ps"* ]]; then
    echo "minecraft"
fi
if [[ "$*" == *"rcon-cli list"* ]]; then
    echo "1 of a max 10 players online: Alice"
fi
EOF
    chmod +x "$STUB_BIN/docker"

    run bash "$SCRIPT"
    [[ "$output" == *"Alice"* ]]
}

@test "skips Minecraft check when container is not running" {
    cat > "$STUB_BIN/docker" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"ps"* ]]; then
    echo ""
fi
EOF
    chmod +x "$STUB_BIN/docker"

    run bash "$SCRIPT"
    [[ "$output" == *"Container not running"* ]]
}

@test "exits 0 when Minecraft container is absent and no other activity" {
    cat > "$STUB_BIN/docker" <<'EOF'
#!/usr/bin/env bash
echo ""
EOF
    chmod +x "$STUB_BIN/docker"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
}

# ── Plex ──────────────────────────────────────────────────────────────────

@test "skips Plex check when PLEX_TOKEN is not set" {
    run bash "$SCRIPT"
    [[ "$output" == *"PLEX_TOKEN not set"* ]]
}

@test "exits 0 with no Plex streams when token is provided" {
    cat > "$STUB_BIN/curl" <<'EOF'
#!/usr/bin/env bash
echo '<MediaContainer size="0"></MediaContainer>'
EOF
    chmod +x "$STUB_BIN/curl"

    PLEX_TOKEN=faketoken run bash "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "detects active Plex streams" {
    cat > "$STUB_BIN/curl" <<'EOF'
#!/usr/bin/env bash
echo '<MediaContainer size="2"><Video title="Breaking Bad" grandparentTitle="Breaking Bad"/><Video title="Inception"/></MediaContainer>'
EOF
    chmod +x "$STUB_BIN/curl"

    PLEX_TOKEN=faketoken run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ACTIVE USERS DETECTED"* ]]
}

@test "prints active Plex stream count" {
    cat > "$STUB_BIN/curl" <<'EOF'
#!/usr/bin/env bash
echo '<MediaContainer size="1"><Video title="Inception"/></MediaContainer>'
EOF
    chmod +x "$STUB_BIN/curl"

    PLEX_TOKEN=faketoken run bash "$SCRIPT"
    [[ "$output" == *"1 active stream"* ]]
}

@test "handles Plex being unreachable" {
    cat > "$STUB_BIN/curl" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$STUB_BIN/curl"

    PLEX_TOKEN=faketoken run bash "$SCRIPT"
    [[ "$output" == *"Could not reach Plex"* ]]
}

# ── Audiobookshelf ────────────────────────────────────────────────────────

@test "detects active Audiobookshelf connections" {
    cat > "$STUB_BIN/ss" <<'EOF'
#!/usr/bin/env bash
echo "tcp   ESTAB  0  0  0.0.0.0:13378  192.168.1.5:51234"
EOF
    chmod +x "$STUB_BIN/ss"

    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ACTIVE USERS DETECTED"* ]]
}

@test "prints Audiobookshelf connection count" {
    cat > "$STUB_BIN/ss" <<'EOF'
#!/usr/bin/env bash
echo "tcp   ESTAB  0  0  0.0.0.0:13378  192.168.1.5:51234"
echo "tcp   ESTAB  0  0  0.0.0.0:13378  192.168.1.6:51235"
EOF
    chmod +x "$STUB_BIN/ss"

    run bash "$SCRIPT"
    [[ "$output" == *"2 active connection"* ]]
}

@test "exits 0 when Audiobookshelf has no connections" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No active connections"* ]]
}

# ── Multi-service ─────────────────────────────────────────────────────────

@test "exits 1 when multiple services have active users" {
    cat > "$STUB_BIN/docker" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"ps"* ]]; then echo "minecraft"; fi
if [[ "$*" == *"rcon-cli list"* ]]; then echo "1 of a max 10 players online: Alice"; fi
EOF
    chmod +x "$STUB_BIN/docker"

    cat > "$STUB_BIN/ss" <<'EOF'
#!/usr/bin/env bash
echo "tcp   ESTAB  0  0  0.0.0.0:13378  192.168.1.5:51234"
EOF
    chmod +x "$STUB_BIN/ss"

    PLEX_TOKEN=faketoken run bash "$SCRIPT"
    [ "$status" -eq 1 ]
}
