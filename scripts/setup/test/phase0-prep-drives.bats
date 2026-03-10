#!/usr/bin/env bats

# Tests for phase0-prep-drives.sh
# Mocks all destructive system commands — safe to run on any machine

SCRIPT="$BATS_TEST_DIRNAME/../phase0-prep-drives.sh"

setup() {
    export TMPDIR="$(mktemp -d)"
    export PATH="$TMPDIR/bin:$PATH"
    mkdir -p "$TMPDIR/bin"

    # Mock lsblk
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

    # Mock findmnt
    cat > "$TMPDIR/bin/findmnt" <<'EOF'
#!/bin/bash
echo "/dev/nvme0n1p3"
EOF
    chmod +x "$TMPDIR/bin/findmnt"

    # Mock sudo — run the command without sudo
    cat > "$TMPDIR/bin/sudo" <<'EOF'
#!/bin/bash
"$@" 2>/dev/null || true
EOF
    chmod +x "$TMPDIR/bin/sudo"

    # Default parted mock — drives have no partition table
    cat > "$TMPDIR/bin/parted" <<'EOF'
#!/bin/bash
if [[ "$*" == *"print"* ]]; then
    dev=$(echo "$*" | grep -o '/dev/[^ ]*')
    echo "Partition Table: unknown"
else
    echo "parted called with: $*"
fi
EOF
    chmod +x "$TMPDIR/bin/parted"
}

teardown() {
    rm -rf "$TMPDIR"
}

@test "skips OS drive" {
    run bash -c "echo 'no' | bash $SCRIPT" 2>&1 || true
    [[ "$output" == *"nvme0n1"*"OS drive (skipping)"* ]]
}

@test "identifies unpartitioned drives for prep" {
    run bash -c "echo 'no' | bash $SCRIPT" 2>&1 || true
    [[ "$output" == *"sda"*"no partition table, will prep"* ]]
    [[ "$output" == *"sdb"*"no partition table, will prep"* ]]
}

@test "aborts when user enters 'no'" {
    run bash -c "echo 'no' | bash $SCRIPT"
    [[ "$output" == *"Aborted"* ]]
}

@test "skips already-partitioned drives" {
    # Override parted to report gpt for sdb
    cat > "$TMPDIR/bin/parted" <<'EOF'
#!/bin/bash
if [[ "$*" == *"print"* ]]; then
    if [[ "$*" == *"sdb"* ]]; then
        echo "Partition Table: gpt"
    else
        echo "Partition Table: unknown"
    fi
else
    echo "parted called with: $*"
fi
EOF
    run bash -c "echo 'no' | bash $SCRIPT" 2>&1 || true
    [[ "$output" == *"sdb"*"already has partition table"* ]]
    [[ "$output" == *"sda"*"no partition table, will prep"* ]]
}

@test "exits cleanly when all drives already partitioned" {
    cat > "$TMPDIR/bin/parted" <<'EOF'
#!/bin/bash
if [[ "$*" == *"print"* ]]; then
    echo "Partition Table: gpt"
else
    echo "parted called with: $*"
fi
EOF
    run bash "$SCRIPT"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Nothing to do"* ]]
}

@test "calls parted to create GPT and partition on unpartitioned drives" {
    run bash -c "echo 'yes' | bash $SCRIPT" 2>&1 || true
    [[ "$output" == *"parted called with"*"mklabel gpt"* ]]
    [[ "$output" == *"parted called with"*"mkpart"* ]]
}

@test "reports completion after prepping drives" {
    run bash -c "echo 'yes' | bash $SCRIPT" 2>&1 || true
    [[ "$output" == *"Phase 0 complete"* ]]
}
