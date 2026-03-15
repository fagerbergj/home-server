#!/usr/bin/env bats

# Tests for phase4-drives.sh (config-driven)
# Mocks all destructive system commands — safe to run on any machine

SCRIPT="$BATS_TEST_DIRNAME/../phase4-drives.sh"

setup() {
    export TMPDIR="$(mktemp -d)"
    export PATH="$TMPDIR/bin:$PATH"

    # Write a base drives.json config
    cat > "$TMPDIR/drives.json" <<'EOF'
{
  "plex01": {
    "device": "/dev/sda1",
    "preserve": false
  },
  "plex02": {
    "device": "/dev/sdd1",
    "preserve": false
  },
  "personal01": {
    "raid_primary": "/dev/sdb1",
    "raid_secondary": "/dev/sdc1"
  }
}
EOF

    mkdir -p "$TMPDIR/bin"

    cat > "$TMPDIR/bin/sudo" <<'EOF'
#!/bin/bash
"$@" 2>/dev/null || true
EOF
    chmod +x "$TMPDIR/bin/sudo"

    cat > "$TMPDIR/bin/jq" <<'EOF'
#!/bin/bash
/usr/bin/jq "$@"
EOF
    chmod +x "$TMPDIR/bin/jq"

    cat > "$TMPDIR/bin/mkfs.ext4" <<'EOF'
#!/bin/bash
echo "mkfs.ext4 called with: $*"
EOF
    chmod +x "$TMPDIR/bin/mkfs.ext4"

    cat > "$TMPDIR/bin/blkid" <<'EOF'
#!/bin/bash
echo "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
EOF
    chmod +x "$TMPDIR/bin/blkid"

    cat > "$TMPDIR/bin/mdadm" <<'EOF'
#!/bin/bash
echo "mdadm called with: $*"
EOF
    chmod +x "$TMPDIR/bin/mdadm"

    for cmd in mount mkdir chown chmod setfacl useradd groupadd usermod apt update-initramfs; do
        cat > "$TMPDIR/bin/$cmd" <<EOF
#!/bin/bash
echo "$cmd called with: \$*"
EOF
        chmod +x "$TMPDIR/bin/$cmd"
    done

    cat > "$TMPDIR/bin/id" <<'EOF'
#!/bin/bash
case "$1" in
    -u) echo "1001" ;;
    plex)        echo "uid=1001(plex)" ;;
    immich)      echo "uid=1002(immich)" ;;
    minecraft)   echo "uid=1003(minecraft)" ;;
    qbittorrent) echo "uid=1004(qbittorrent)" ;;
    *) echo "uid=1000(jason)" ;;
esac
EOF
    chmod +x "$TMPDIR/bin/id"

    cat > "$TMPDIR/bin/getent" <<'EOF'
#!/bin/bash
case "$2" in
    plex-rw)     echo "plex-rw:x:2001:" ;;
    plex-ro)     echo "plex-ro:x:2002:" ;;
    personal-rw) echo "personal-rw:x:2003:" ;;
    *) return 1 ;;
esac
EOF
    chmod +x "$TMPDIR/bin/getent"

    grep -qF 'drives.json' "$SCRIPT" && \
        export SCRIPT_PATCHED="$(sed "s|SCRIPT_DIR/drives.json|TMPDIR/drives.json|g" <<< "$SCRIPT")" || true
}

teardown() {
    rm -rf "$TMPDIR"
}

run_script() {
    BATS_TEST_DIRNAME="$TMPDIR" run bash -c \
        "SCRIPT_DIR='$TMPDIR' && $(sed 's|SCRIPT_DIR=.*|SCRIPT_DIR='"$TMPDIR"'|' "$SCRIPT")" 2>&1 || true
}

@test "aborts if drives.json not found" {
    rm "$TMPDIR/drives.json"
    run bash -c "SCRIPT_DIR='$TMPDIR' bash $SCRIPT"
    [[ "$output" == *"not found"* ]]
    [[ "$status" -ne 0 ]]
}

@test "aborts when user enters 'no'" {
    run bash -c "SCRIPT_DIR='$TMPDIR' echo 'no' | bash $SCRIPT"
    [[ "$output" == *"Aborted"* ]]
}

@test "formats plex01 when preserve is false" {
    run bash -c "SCRIPT_DIR='$TMPDIR' printf 'yes\n\n' | bash $SCRIPT" 2>&1 || true
    [[ "$output" == *"mkfs.ext4 called with"*"sda1"* ]]
}

@test "skips formatting plex01 when preserve is true" {
    jq '.plex01.preserve = true' "$TMPDIR/drives.json" > "$TMPDIR/drives.tmp.json"
    mv "$TMPDIR/drives.tmp.json" "$TMPDIR/drives.json"
    run bash -c "SCRIPT_DIR='$TMPDIR' printf 'yes\n\n' | bash $SCRIPT" 2>&1 || true
    [[ "$output" == *"preserving existing data"* ]]
    [[ "$output" != *"mkfs.ext4 called with"*"sda1"* ]]
}

@test "formats plex02 when present and preserve is false" {
    run bash -c "SCRIPT_DIR='$TMPDIR' printf 'yes\n\n' | bash $SCRIPT" 2>&1 || true
    [[ "$output" == *"mkfs.ext4 called with"*"sdd1"* ]]
}

@test "creates RAID with --force using configured devices" {
    run bash -c "SCRIPT_DIR='$TMPDIR' printf 'yes\n\n' | bash $SCRIPT" 2>&1 || true
    [[ "$output" == *"mdadm called with"*"--force"* ]]
    [[ "$output" == *"sdb1"* ]]
    [[ "$output" == *"sdc1"* ]]
}

@test "prints UID/GID summary at end" {
    run bash -c "SCRIPT_DIR='$TMPDIR' printf 'yes\n\n' | bash $SCRIPT" 2>&1 || true
    [[ "$output" == *"PUID (plex)"* ]]
    [[ "$output" == *"PGID (plex-rw)"* ]]
}

@test "skips plex02 when not in config" {
    jq 'del(.plex02)' "$TMPDIR/drives.json" > "$TMPDIR/drives.tmp.json"
    mv "$TMPDIR/drives.tmp.json" "$TMPDIR/drives.json"
    run bash -c "SCRIPT_DIR='$TMPDIR' printf 'yes\n\n' | bash $SCRIPT" 2>&1 || true
    [[ "$output" != *"mkfs.ext4 called with"*"sdd1"* ]]
}
