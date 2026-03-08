#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../phase2-nvidia.sh"

setup() {
    export TMPDIR="$(mktemp -d)"
    export PATH="$TMPDIR/bin:$PATH"
    mkdir -p "$TMPDIR/bin"

    for cmd in sudo apt reboot; do
        cat > "$TMPDIR/bin/$cmd" <<EOF
#!/bin/bash
echo "$cmd called with: \$*"
EOF
        chmod +x "$TMPDIR/bin/$cmd"
    done

    cat > "$TMPDIR/bin/ubuntu-drivers" <<'EOF'
#!/bin/bash
echo "ubuntu-drivers called with: $*"
EOF
    chmod +x "$TMPDIR/bin/ubuntu-drivers"

    # Mock sleep so tests don't wait
    cat > "$TMPDIR/bin/sleep" <<'EOF'
#!/bin/bash
echo "sleep called"
EOF
    chmod +x "$TMPDIR/bin/sleep"
}

teardown() {
    rm -rf "$TMPDIR"
}

@test "installs ubuntu-drivers-common" {
    run bash "$SCRIPT"
    [[ "$output" == *"ubuntu-drivers-common"* ]]
}

@test "runs ubuntu-drivers autoinstall" {
    run bash "$SCRIPT"
    [[ "$output" == *"autoinstall"* ]]
}

@test "reboots after install" {
    run bash "$SCRIPT"
    [[ "$output" == *"reboot"* ]]
}
