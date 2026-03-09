#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../phase3-monitoring.sh"

setup() {
    export TMPDIR="$(mktemp -d)"
    export PATH="$TMPDIR/bin:$PATH"
    mkdir -p "$TMPDIR/bin"

    for cmd in sudo apt; do
        cat > "$TMPDIR/bin/$cmd" <<EOF
#!/bin/bash
echo "$cmd called with: \$*"
EOF
        chmod +x "$TMPDIR/bin/$cmd"
    done
}

teardown() {
    rm -rf "$TMPDIR"
}

@test "installs btop" {
    run bash "$SCRIPT"
    [[ "$output" == *"btop"* ]]
}

@test "installs nvtop" {
    run bash "$SCRIPT"
    [[ "$output" == *"nvtop"* ]]
}

@test "prints usage hints" {
    run bash "$SCRIPT"
    [[ "$output" == *"btop"* ]]
    [[ "$output" == *"nvtop"* ]]
    [[ "$output" == *"GPU"* ]]
}
