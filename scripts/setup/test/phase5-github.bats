#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../phase5-github.sh"

setup() {
    export TMPDIR="$(mktemp -d)"
    export PATH="$TMPDIR/bin:$PATH"
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME/.ssh"
    mkdir -p "$TMPDIR/bin"

    # Mock ssh-keygen
    cat > "$TMPDIR/bin/ssh-keygen" <<EOF
#!/bin/bash
echo "ssh-keygen called with: \$*"
echo "ssh-ed25519 AAAAFAKEKEY home-server" > "$HOME/.ssh/id_ed25519.pub"
touch "$HOME/.ssh/id_ed25519"
EOF
    chmod +x "$TMPDIR/bin/ssh-keygen"

    # Mock cat
    cat > "$TMPDIR/bin/cat" <<EOF
#!/bin/bash
if [[ "\$1" == *"id_ed25519.pub"* ]]; then
    echo "ssh-ed25519 AAAAFAKEKEY home-server"
else
    /bin/cat "\$@"
fi
EOF
    chmod +x "$TMPDIR/bin/cat"

    # Mock ssh
    cat > "$TMPDIR/bin/ssh" <<'EOF'
#!/bin/bash
echo "Hi fagerbergj! You've successfully authenticated"
EOF
    chmod +x "$TMPDIR/bin/ssh"

    # Mock git
    cat > "$TMPDIR/bin/git" <<'EOF'
#!/bin/bash
echo "git called with: $*"
mkdir -p ~/workspace/home-server
EOF
    chmod +x "$TMPDIR/bin/git"

    # Mock read (auto ENTER for the GitHub prompt)
    export BASH_ENV="$TMPDIR/bash_env"
    cat > "$TMPDIR/bash_env" <<'EOF'
read() { echo ""; }
EOF
}

teardown() {
    rm -rf "$TMPDIR"
}

@test "generates SSH key when none exists" {
    rm -f "$HOME/.ssh/id_ed25519"
    run bash "$SCRIPT"
    [[ "$output" == *"ssh-keygen"* ]]
}

@test "skips key generation if key already exists" {
    touch "$HOME/.ssh/id_ed25519"
    run bash "$SCRIPT"
    [[ "$output" == *"already exists"* ]]
}

@test "prints public key for user to copy" {
    run bash "$SCRIPT"
    [[ "$output" == *"AAAAFAKEKEY"* ]]
}

@test "verifies github connection" {
    run bash "$SCRIPT"
    [[ "$output" == *"successfully authenticated"* ]]
}

@test "clones repo if not present" {
    run bash "$SCRIPT"
    [[ "$output" == *"git called"* ]]
}

@test "skips clone if repo already exists" {
    mkdir -p "$HOME/../workspace/home-server" 2>/dev/null || true
    mkdir -p ~/workspace/home-server
    run bash "$SCRIPT"
    [[ "$output" == *"already exists"* ]]
}
