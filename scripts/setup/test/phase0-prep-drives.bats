#!/usr/bin/env bats

# Tests for phase0-prep-drives.sh (ZFS-era wipe flow).
# Mocks lsblk/findmnt/wipefs/sgdisk so destructive commands never touch the
# real system.

SCRIPT="$BATS_TEST_DIRNAME/../phase0-prep-drives.sh"

setup() {
    export TMPDIR="$(mktemp -d)"
    export PATH="$TMPDIR/bin:$PATH"
    mkdir -p "$TMPDIR/bin"

    cat > "$TMPDIR/bin/lsblk" <<'EOF'
#!/bin/bash
if [[ "$*" == *"-d -b -o NAME,SIZE"* ]]; then
    echo "NAME SIZE"
    echo "sda  4000000000000"
    echo "sdb  1000000000000"
    echo "nvme0n1 256000000000"
elif [[ "$*" == *"-d -o NAME,SIZE"* ]]; then
    echo "NAME SIZE"
    echo "sda  3.6T"
    echo "sdb  931.5G"
    echo "nvme0n1 238.5G"
elif [[ "$*" == *"-no pkname"* ]]; then
    echo "nvme0n1"
fi
EOF
    chmod +x "$TMPDIR/bin/lsblk"

    cat > "$TMPDIR/bin/findmnt" <<'EOF'
#!/bin/bash
echo "/dev/nvme0n1p3"
EOF
    chmod +x "$TMPDIR/bin/findmnt"

    cat > "$TMPDIR/bin/sudo" <<'EOF'
#!/bin/bash
"$@" 2>/dev/null || true
EOF
    chmod +x "$TMPDIR/bin/sudo"

    # Default: every drive has signatures (wipefs -n prints lines)
    cat > "$TMPDIR/bin/wipefs" <<'EOF'
#!/bin/bash
echo "wipefs called with: $*" >> "$TMPDIR/wipefs.calls"
if [[ "$1" == "-n" ]]; then
    echo "DEVICE OFFSET TYPE UUID LABEL"
    echo "fake   0      ext4 abcd  -"
    exit 0
fi
EOF
    chmod +x "$TMPDIR/bin/wipefs"

    cat > "$TMPDIR/bin/sgdisk" <<'EOF'
#!/bin/bash
echo "sgdisk called with: $*" >> "$TMPDIR/sgdisk.calls"
EOF
    chmod +x "$TMPDIR/bin/sgdisk"
}

teardown() {
    rm -rf "$TMPDIR"
}

@test "skips OS drive" {
    run bash -c "echo 'no' | bash $SCRIPT" 2>&1 || true
    [[ "$output" == *"nvme0n1"*"OS drive (skipping)"* ]]
}

@test "identifies drives with signatures for wiping" {
    run bash -c "echo 'no' | bash $SCRIPT" 2>&1 || true
    [[ "$output" == *"sda"*"will wipe"* ]]
    [[ "$output" == *"sdb"*"will wipe"* ]]
}

@test "aborts when user enters 'no'" {
    run bash -c "echo 'no' | bash $SCRIPT"
    [[ "$output" == *"Aborted"* ]]
}

@test "skips already-clean drives" {
    # Override wipefs -n to report no signatures for sdb
    cat > "$TMPDIR/bin/wipefs" <<'EOF'
#!/bin/bash
echo "wipefs called with: $*" >> "$TMPDIR/wipefs.calls"
if [[ "$1" == "-n" ]]; then
    if [[ "$*" == *"sdb"* ]]; then
        # Empty output = no signatures
        exit 0
    fi
    echo "DEVICE OFFSET TYPE UUID LABEL"
    echo "fake   0      ext4 abcd  -"
    exit 0
fi
EOF
    run bash -c "echo 'no' | bash $SCRIPT" 2>&1 || true
    [[ "$output" == *"sdb"*"already clean"* ]]
    [[ "$output" == *"sda"*"will wipe"* ]]
}

@test "exits cleanly when all non-OS drives already clean" {
    cat > "$TMPDIR/bin/wipefs" <<'EOF'
#!/bin/bash
if [[ "$1" == "-n" ]]; then exit 0; fi
EOF
    run bash "$SCRIPT"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Nothing to do"* ]]
}

@test "calls wipefs -a on dirty drives after confirmation" {
    run bash -c "echo 'yes' | bash $SCRIPT" 2>&1 || true
    grep -q "wipefs called with: -a /dev/sda" "$TMPDIR/wipefs.calls"
    grep -q "wipefs called with: -a /dev/sdb" "$TMPDIR/wipefs.calls"
}

@test "calls sgdisk --zap-all on dirty drives after confirmation" {
    run bash -c "echo 'yes' | bash $SCRIPT" 2>&1 || true
    grep -q "sgdisk called with: --zap-all /dev/sda" "$TMPDIR/sgdisk.calls"
    grep -q "sgdisk called with: --zap-all /dev/sdb" "$TMPDIR/sgdisk.calls"
}

@test "does not invoke wipefs -a or sgdisk on the OS drive" {
    run bash -c "echo 'yes' | bash $SCRIPT" 2>&1 || true
    ! grep -q "wipefs called with: -a /dev/nvme0n1" "$TMPDIR/wipefs.calls"
    ! grep -q "sgdisk called with: --zap-all /dev/nvme0n1" "$TMPDIR/sgdisk.calls"
}

@test "reports completion after wiping drives" {
    run bash -c "echo 'yes' | bash $SCRIPT" 2>&1 || true
    [[ "$output" == *"Phase 0 complete"* ]]
}
