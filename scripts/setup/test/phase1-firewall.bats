#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../phase1-firewall.sh"

setup() {
    export TMPDIR="$(mktemp -d)"
    export PATH="$TMPDIR/bin:$PATH"
    mkdir -p "$TMPDIR/bin"

    cat > "$TMPDIR/bin/sudo" <<'EOF'
#!/bin/bash
"$@" 2>/dev/null || true
EOF
    chmod +x "$TMPDIR/bin/sudo"

    cat > "$TMPDIR/bin/ufw" <<'EOF'
#!/bin/bash
echo "ufw called with: $*"
EOF
    chmod +x "$TMPDIR/bin/ufw"
}

teardown() {
    rm -rf "$TMPDIR"
}

@test "allows port 80" {
    run bash "$SCRIPT"
    [[ "$output" == *"80/tcp"* ]]
}

@test "allows port 443" {
    run bash "$SCRIPT"
    [[ "$output" == *"443/tcp"* ]]
}

@test "allows port 25565 for Minecraft" {
    run bash "$SCRIPT"
    [[ "$output" == *"25565/tcp"* ]]
}

@test "enables ufw" {
    run bash "$SCRIPT"
    [[ "$output" == *"enable"* ]]
}

@test "prints ufw status" {
    run bash "$SCRIPT"
    [[ "$output" == *"status"* ]]
}
