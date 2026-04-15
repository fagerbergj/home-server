#!/usr/bin/env bats
# Tests for scripts/check-active-users.sh
#
# Stubs docker and curl so nothing touches a real server.

setup() {
    TEST_DIR="$(mktemp -d)"
    STUB_BIN="$TEST_DIR/bin"
    mkdir -p "$STUB_BIN"

    # Copy script under test — stubs handle isolation
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

    # Default curl stub: routes by URL pattern
    cat > "$STUB_BIN/curl" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"/api/sessions/open"* ]]; then
    echo '{"sessions":[]}'
elif [[ "$*" == *"status/sessions"* ]]; then
    echo '<MediaContainer size="0"></MediaContainer>'
fi
EOF
    chmod +x "$STUB_BIN/curl"

    export PATH="$STUB_BIN:$PATH"
    export TEST_DIR SCRIPT
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ── All clear ─────────────────────────────────────────────────────────────

@test "exits 0 when no active users on any service" {
    PLEX_TOKEN=faketoken ABS_API_KEY=fakekey run bash "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "prints all clear message when no active users" {
    PLEX_TOKEN=faketoken ABS_API_KEY=fakekey run bash "$SCRIPT"
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

    PLEX_TOKEN=faketoken ABS_API_KEY=fakekey run bash "$SCRIPT"
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

    PLEX_TOKEN=faketoken ABS_API_KEY=fakekey run bash "$SCRIPT"
    [ "$status" -eq 0 ]
}

# ── Plex ──────────────────────────────────────────────────────────────────

@test "skips Plex check when PLEX_TOKEN is not set" {
    run bash "$SCRIPT"
    [[ "$output" == *"PLEX_TOKEN not set"* ]]
}

@test "exits 0 with no Plex streams when token is provided" {
    PLEX_TOKEN=faketoken ABS_API_KEY=fakekey run bash "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "detects active Plex streams" {
    cat > "$STUB_BIN/curl" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"/api/sessions/open"* ]]; then
    echo '{"sessions":[]}'
elif [[ "$*" == *"status/sessions"* ]]; then
    echo '<MediaContainer size="2"><Video title="Breaking Bad"/><Video title="Inception"/></MediaContainer>'
fi
EOF
    chmod +x "$STUB_BIN/curl"

    PLEX_TOKEN=faketoken ABS_API_KEY=fakekey run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ACTIVE USERS DETECTED"* ]]
}

@test "prints Plex stream title and time in" {
    cat > "$STUB_BIN/curl" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"/api/sessions/open"* ]]; then
    echo '{"sessions":[]}'
elif [[ "$*" == *"status/sessions"* ]]; then
    echo '<MediaContainer size="1"><Video title="Inception" viewOffset="720000"><User title="jason"/><Player title="Apple TV"/></Video></MediaContainer>'
fi
EOF
    chmod +x "$STUB_BIN/curl"

    PLEX_TOKEN=faketoken ABS_API_KEY=fakekey run bash "$SCRIPT"
    [[ "$output" == *"Inception"* ]]
    [[ "$output" == *"Apple TV"* ]]
    [[ "$output" == *"12m in"* ]]
}

@test "handles Plex being unreachable" {
    cat > "$STUB_BIN/curl" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"/api/sessions/open"* ]]; then
    echo '{"sessions":[]}'
elif [[ "$*" == *"status/sessions"* ]]; then
    exit 1
fi
EOF
    chmod +x "$STUB_BIN/curl"

    PLEX_TOKEN=faketoken ABS_API_KEY=fakekey run bash "$SCRIPT"
    [[ "$output" == *"Could not reach Plex"* ]]
}

# ── Audiobookshelf ────────────────────────────────────────────────────────

@test "skips ABS check when ABS_API_KEY is not set" {
    run bash "$SCRIPT"
    [[ "$output" == *"ABS_API_KEY not set"* ]]
}

@test "detects active Audiobookshelf streams" {
    cat > "$STUB_BIN/curl" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"/api/sessions/open"* ]]; then
    echo '{"sessions":[{"id":"abc123","displayTitle":"Morning Star"}]}'
elif [[ "$*" == *"status/sessions"* ]]; then
    echo '<MediaContainer size="0"></MediaContainer>'
fi
EOF
    chmod +x "$STUB_BIN/curl"

    PLEX_TOKEN=faketoken ABS_API_KEY=fakekey run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ACTIVE USERS DETECTED"* ]]
}

@test "prints active Audiobookshelf stream title" {
    cat > "$STUB_BIN/curl" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"/api/sessions/open"* ]]; then
    echo '{"sessions":[{"id":"abc123","displayTitle":"Morning Star"}]}'
elif [[ "$*" == *"status/sessions"* ]]; then
    echo '<MediaContainer size="0"></MediaContainer>'
fi
EOF
    chmod +x "$STUB_BIN/curl"

    PLEX_TOKEN=faketoken ABS_API_KEY=fakekey run bash "$SCRIPT"
    [[ "$output" == *"Morning Star"* ]]
}

@test "exits 0 when Audiobookshelf has no active streams" {
    PLEX_TOKEN=faketoken ABS_API_KEY=fakekey run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No active streams"* ]]
}

@test "handles Audiobookshelf being unreachable" {
    cat > "$STUB_BIN/curl" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"/api/sessions/open"* ]]; then
    exit 1
elif [[ "$*" == *"status/sessions"* ]]; then
    echo '<MediaContainer size="0"></MediaContainer>'
fi
EOF
    chmod +x "$STUB_BIN/curl"

    PLEX_TOKEN=faketoken ABS_API_KEY=fakekey run bash "$SCRIPT"
    [[ "$output" == *"Could not reach Audiobookshelf"* ]]
}

# ── Multi-service ─────────────────────────────────────────────────────────

@test "exits 1 when multiple services have active users" {
    cat > "$STUB_BIN/docker" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"ps"* ]]; then echo "minecraft"; fi
if [[ "$*" == *"rcon-cli list"* ]]; then echo "1 of a max 10 players online: Alice"; fi
EOF
    chmod +x "$STUB_BIN/docker"

    cat > "$STUB_BIN/curl" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"/api/sessions/open"* ]]; then
    echo '{"sessions":[{"id":"abc123","displayTitle":"Morning Star"}]}'
elif [[ "$*" == *"status/sessions"* ]]; then
    echo '<MediaContainer size="0"></MediaContainer>'
fi
EOF
    chmod +x "$STUB_BIN/curl"

    PLEX_TOKEN=faketoken ABS_API_KEY=fakekey run bash "$SCRIPT"
    [ "$status" -eq 1 ]
}
