#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../phase5-docker.sh"

setup() {
    export TMPDIR="$(mktemp -d)"
    export PATH="$TMPDIR/bin:$PATH"
    mkdir -p "$TMPDIR/bin"

    # All commands that need mocking in phase4
    for cmd in apt systemctl usermod; do
        cat > "$TMPDIR/bin/$cmd" <<EOF
#!/bin/bash
echo "$cmd called with: \$*"
EOF
        chmod +x "$TMPDIR/bin/$cmd"
    done

    # sudo — pass through to mocked commands, suppress errors
    cat > "$TMPDIR/bin/sudo" <<'EOF'
#!/bin/bash
"$@" 2>/dev/null || true
EOF
    chmod +x "$TMPDIR/bin/sudo"

    # curl — output something plausible so pipelines don't SIGPIPE
    cat > "$TMPDIR/bin/curl" <<'EOF'
#!/bin/bash
echo "curl called with: $*"
echo "deb https://example.com stable main"
EOF
    chmod +x "$TMPDIR/bin/curl"

    # tee — must consume stdin to avoid SIGPIPE in pipelines
    cat > "$TMPDIR/bin/tee" <<'EOF'
#!/bin/bash
echo "tee called with: $*"
cat > /dev/null
EOF
    chmod +x "$TMPDIR/bin/tee"

    # gpg — consume stdin (piped from curl)
    cat > "$TMPDIR/bin/gpg" <<'EOF'
#!/bin/bash
echo "gpg called with: $*"
cat > /dev/null
EOF
    chmod +x "$TMPDIR/bin/gpg"

    # sed — pass through (used in pipeline, needs to consume and emit)
    cat > "$TMPDIR/bin/sed" <<'EOF'
#!/bin/bash
echo "sed called with: $*"
cat > /dev/null
EOF
    chmod +x "$TMPDIR/bin/sed"

    # install — used for creating /etc/apt/keyrings
    cat > "$TMPDIR/bin/install" <<'EOF'
#!/bin/bash
echo "install called with: $*"
EOF
    chmod +x "$TMPDIR/bin/install"

    # dpkg — returns architecture
    cat > "$TMPDIR/bin/dpkg" <<'EOF'
#!/bin/bash
echo "amd64"
EOF
    chmod +x "$TMPDIR/bin/dpkg"

    # nvidia-ctk
    cat > "$TMPDIR/bin/nvidia-ctk" <<'EOF'
#!/bin/bash
echo "nvidia-ctk called with: $*"
EOF
    chmod +x "$TMPDIR/bin/nvidia-ctk"

    # docker — simulate GPU verify output
    cat > "$TMPDIR/bin/docker" <<'EOF'
#!/bin/bash
echo "docker called with: $*"
echo "GTX 1070 Ti"
EOF
    chmod +x "$TMPDIR/bin/docker"
}

teardown() {
    rm -rf "$TMPDIR"
}

@test "adds Docker GPG key" {
    run bash "$SCRIPT"
    [[ "$output" == *"docker.gpg"* ]]
}

@test "installs docker packages" {
    run bash "$SCRIPT"
    [[ "$output" == *"docker-ce"* ]]
}

@test "adds user to docker group" {
    run bash "$SCRIPT"
    [[ "$output" == *"docker"* ]]
}

@test "installs nvidia-container-toolkit" {
    run bash "$SCRIPT"
    [[ "$output" == *"nvidia-container-toolkit"* ]]
}

@test "configures nvidia runtime for docker" {
    run bash "$SCRIPT"
    [[ "$output" == *"nvidia-ctk"* ]]
}

@test "restarts docker after nvidia config" {
    run bash "$SCRIPT"
    [[ "$output" == *"restart"* ]]
}

@test "verifies GPU accessible from docker" {
    run bash "$SCRIPT"
    [[ "$output" == *"--gpus all"* ]]
}
