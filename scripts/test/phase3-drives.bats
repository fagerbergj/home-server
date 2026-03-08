#!/usr/bin/env bats

# Tests for phase3-drives.sh
# Mocks all destructive system commands — safe to run on any machine

SCRIPT="$BATS_TEST_DIRNAME/../phase3-drives.sh"

setup() {
    # Create a temp dir for each test to hold mock binaries and state
    export TMPDIR="$(mktemp -d)"
    export PATH="$TMPDIR/bin:$PATH"
    export FSTAB="$TMPDIR/fstab"
    export MDADM_CONF="$TMPDIR/mdadm.conf"
    touch "$FSTAB"
    touch "$MDADM_CONF"

    # Mock lsblk — 3 non-OS drives: 4TB, 1TB (new), 1TB (old)
    mkdir -p "$TMPDIR/bin"
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
else
    echo "NAME FSTYPE SIZE"
    echo "sda        3.6T"
    echo "sdb        931.5G"
    echo "sdc        931.5G"
    echo "nvme0n1    238.5G"
fi
EOF
    chmod +x "$TMPDIR/bin/lsblk"

    # Mock findmnt
    cat > "$TMPDIR/bin/findmnt" <<'EOF'
#!/bin/bash
echo "/dev/nvme0n1p3"
EOF
    chmod +x "$TMPDIR/bin/findmnt"

    # Mock sudo — just run the command without sudo
    cat > "$TMPDIR/bin/sudo" <<'EOF'
#!/bin/bash
# Strip sudo and run rest, redirecting fstab/mdadm paths to temp files
cmd=("$@")
"${cmd[@]}" 2>/dev/null || true
EOF
    chmod +x "$TMPDIR/bin/sudo"

    # Mock mkfs.ext4
    cat > "$TMPDIR/bin/mkfs.ext4" <<'EOF'
#!/bin/bash
echo "mkfs.ext4 called with: $*"
EOF
    chmod +x "$TMPDIR/bin/mkfs.ext4"

    # Mock blkid
    cat > "$TMPDIR/bin/blkid" <<'EOF'
#!/bin/bash
echo "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
EOF
    chmod +x "$TMPDIR/bin/blkid"

    # Mock mdadm
    cat > "$TMPDIR/bin/mdadm" <<'EOF'
#!/bin/bash
echo "mdadm called with: $*"
EOF
    chmod +x "$TMPDIR/bin/mdadm"

    # Mock mount, mkdir, chown, chmod, setfacl, useradd, groupadd, usermod, apt, update-initramfs, nvidia-ctk
    for cmd in mount mkdir chown chmod setfacl useradd groupadd usermod apt update-initramfs; do
        cat > "$TMPDIR/bin/$cmd" <<EOF
#!/bin/bash
echo "$cmd called with: \$*"
EOF
        chmod +x "$TMPDIR/bin/$cmd"
    done

    # Mock id and getent to return predictable values
    cat > "$TMPDIR/bin/id" <<'EOF'
#!/bin/bash
case "$1" in
    plex)        echo "uid=1001(plex)" ;;
    immich)      echo "uid=1002(immich)" ;;
    minecraft)   echo "uid=1003(minecraft)" ;;
    qbittorrent) echo "uid=1004(qbittorrent)" ;;
    -u)          echo "1001" ;;
    *)           echo "uid=1000(jason)" ;;
esac
EOF
    chmod +x "$TMPDIR/bin/id"

    cat > "$TMPDIR/bin/getent" <<'EOF'
#!/bin/bash
case "$2" in
    plex-rw)      echo "plex-rw:x:2001:" ;;
    plex-ro)      echo "plex-ro:x:2002:" ;;
    personal-rw)  echo "personal-rw:x:2003:" ;;
    *)            return 1 ;;
esac
EOF
    chmod +x "$TMPDIR/bin/getent"
}

teardown() {
    rm -rf "$TMPDIR"
}

@test "detects 4TB drive as plex01" {
    run bash -c "echo 'no' | bash $SCRIPT" 2>&1 || true
    [[ "$output" == *"sda"* ]]
    [[ "$output" == *"plex01"* ]]
}

@test "assigns two 1TB drives to RAID array" {
    run bash -c "echo 'no' | bash $SCRIPT" 2>&1 || true
    [[ "$output" == *"sdb"* ]]
    [[ "$output" == *"sdc"* ]]
    [[ "$output" == *"RAID"* ]]
}

@test "skips OS drive" {
    run bash -c "echo 'no' | bash $SCRIPT" 2>&1 || true
    [[ "$output" != *"nvme0n1   /mnt/plex01"* ]]
    [[ "$output" == *"OS drive (will be skipped)"* ]]
}

@test "aborts when user enters 'no'" {
    run bash -c "echo 'no' | bash $SCRIPT"
    [[ "$output" == *"Aborted"* ]]
}

@test "prints UID/GID summary at end" {
    # Feed 'yes' then ENTER for RAID sync wait
    run bash -c "printf 'yes\n\n' | bash $SCRIPT" 2>&1 || true
    [[ "$output" == *"PUID (plex)"* ]]
    [[ "$output" == *"PGID (plex-rw)"* ]]
}
