#!/usr/bin/env bats

# Tests for phase4-detect-drives.sh
# Mocks all system commands — safe to run on any machine

SCRIPT="$BATS_TEST_DIRNAME/../phase4-detect-drives.sh"

setup() {
    export TMPDIR="$(mktemp -d)"
    export PATH="$TMPDIR/bin:$PATH"
    mkdir -p "$TMPDIR/bin"

    # Mock lsblk — 4 non-OS drives: 4TB, 1TB, 1TB, 640GB + nvme OS drive
    cat > "$TMPDIR/bin/lsblk" <<'EOF'
#!/bin/bash
if [[ "$*" == *"-d -b -o NAME,SIZE"* ]]; then
    echo "NAME SIZE"
    echo "sda  4000000000000"
    echo "sdb  1000000000000"
    echo "sdc  1000000000000"
    echo "sdd  640000000000"
    echo "nvme0n1 256000000000"
elif [[ "$*" == *"-d -o NAME,SIZE"* ]]; then
    echo "NAME SIZE"
    echo "sda  3.6T"
    echo "sdb  931.5G"
    echo "sdc  931.5G"
    echo "sdd  596.2G"
    echo "nvme0n1 238.5G"
elif [[ "$*" == *"-no pkname"* ]]; then
    echo "nvme0n1"
else
    echo "NAME SIZE"
    echo "sda  3.6T"
fi
EOF
    chmod +x "$TMPDIR/bin/lsblk"

    cat > "$TMPDIR/bin/findmnt" <<'EOF'
#!/bin/bash
echo "/dev/nvme0n1p3"
EOF
    chmod +x "$TMPDIR/bin/findmnt"

    # Mock blkid — no existing filesystems by default
    cat > "$TMPDIR/bin/blkid" <<'EOF'
#!/bin/bash
if [[ "$*" == *"-s TYPE"* ]]; then
    exit 0
fi
echo "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
EOF
    chmod +x "$TMPDIR/bin/blkid"
}

teardown() {
    rm -rf "$TMPDIR"
}

@test "assigns largest drive as plex01" {
    run bash -c "SCRIPT_DIR='$TMPDIR' bash $SCRIPT"
    [[ "$output" == *"plex01"*"sda1"* ]]
}

@test "assigns next two drives as RAID primary and secondary" {
    run bash -c "SCRIPT_DIR='$TMPDIR' bash $SCRIPT"
    [[ "$output" == *"raid primary"*"sdb1"* ]]
    [[ "$output" == *"raid secondary"*"sdc1"* ]]
}

@test "assigns fourth drive as plex02" {
    run bash -c "SCRIPT_DIR='$TMPDIR' bash $SCRIPT"
    [[ "$output" == *"plex02"*"sdd1"* ]]
}

@test "excludes OS drive from assignments" {
    run bash -c "SCRIPT_DIR='$TMPDIR' bash $SCRIPT"
    [[ "$output" != *"plex01"*"nvme"* ]]
    [[ "$output" == *"nvme0n1"*"excluded"* || "$output" == *"nvme"* ]]
}

@test "sets preserve false when no filesystem exists" {
    run bash -c "SCRIPT_DIR='$TMPDIR' bash $SCRIPT"
    output_json=$(cat "$TMPDIR/drives.json")
    [[ "$(echo "$output_json" | jq -r '.plex01.preserve')" == "false" ]]
}

@test "sets preserve true when filesystem already exists on plex01" {
    cat > "$TMPDIR/bin/blkid" <<'EOF'
#!/bin/bash
if [[ "$*" == *"-s TYPE"* && "$*" == *"sda1"* ]]; then
    echo "ext4"
    exit 0
fi
exit 0
EOF
    run bash -c "SCRIPT_DIR='$TMPDIR' bash $SCRIPT"
    output_json=$(cat "$TMPDIR/drives.json")
    [[ "$(echo "$output_json" | jq -r '.plex01.preserve')" == "true" ]]
}

@test "writes valid JSON to drives.json" {
    run bash -c "SCRIPT_DIR='$TMPDIR' bash $SCRIPT"
    run jq . "$TMPDIR/drives.json"
    [[ "$status" -eq 0 ]]
}

@test "written config contains expected device paths" {
    run bash -c "SCRIPT_DIR='$TMPDIR' bash $SCRIPT"
    output_json=$(cat "$TMPDIR/drives.json")
    [[ "$(echo "$output_json" | jq -r '.plex01.device')" == "/dev/sda1" ]]
    [[ "$(echo "$output_json" | jq -r '.personal01.raid_primary')" == "/dev/sdb1" ]]
    [[ "$(echo "$output_json" | jq -r '.personal01.raid_secondary')" == "/dev/sdc1" ]]
    [[ "$(echo "$output_json" | jq -r '.plex02.device')" == "/dev/sdd1" ]]
}

@test "omits plex02 from config when only 3 drives present" {
    cat > "$TMPDIR/bin/lsblk" <<'EOF'
#!/bin/bash
if [[ "$*" == *"-d -b -o NAME,SIZE"* ]]; then
    echo "NAME SIZE"
    echo "sda  4000000000000"
    echo "sdb  1000000000000"
    echo "sdc  1000000000000"
    echo "nvme0n1 256000000000"
elif [[ "$*" == *"-d -o NAME,SIZE"* ]]; then
    echo "NAME SIZE"
    echo "sda  3.6T"
    echo "sdb  931.5G"
    echo "sdc  931.5G"
    echo "nvme0n1 238.5G"
elif [[ "$*" == *"-no pkname"* ]]; then
    echo "nvme0n1"
fi
EOF
    run bash -c "SCRIPT_DIR='$TMPDIR' bash $SCRIPT"
    output_json=$(cat "$TMPDIR/drives.json")
    [[ "$(echo "$output_json" | jq -r '.plex02 // "absent"')" == "absent" ]]
}

@test "fails with fewer than 3 non-OS drives" {
    cat > "$TMPDIR/bin/lsblk" <<'EOF'
#!/bin/bash
if [[ "$*" == *"-d -b -o NAME,SIZE"* ]]; then
    echo "NAME SIZE"
    echo "sda  4000000000000"
    echo "nvme0n1 256000000000"
elif [[ "$*" == *"-no pkname"* ]]; then
    echo "nvme0n1"
fi
EOF
    run bash -c "SCRIPT_DIR='$TMPDIR' bash $SCRIPT"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Error"* ]]
}
