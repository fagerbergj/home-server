#!/usr/bin/env bats
# Tests for scripts/setup/phase4-drives.sh

load 'test_helper.bash'

SRC_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../setup" && pwd)/phase4-drives.sh"

setup() {
    TEST_DIR="$(mktemp -d)"
    export TEST_DIR
    stub_bin_init
    make_sudo_stub
    install_fs_stubs
    make_getent_stub
    make_id_stub
    seed_default_users_and_groups

    make_stub useradd
    make_stub groupadd
    make_stub usermod

    # zpool stub: `list -H -o name <p>` → exit 1 by default (pool absent).
    #             `create ...`           → record call.
    #             `status <p>`           → no-op.
    cat > "$STUB_BIN/zpool" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$TEST_DIR/zpool.calls"
case "$1" in
    list)
        pool="${@: -1}"
        [[ -f "$TEST_DIR/pools/$pool" ]] && exit 0
        exit 1
        ;;
    create)
        # Last non-flag word after the layout keyword is what the script passes.
        pool=""
        for arg in "$@"; do
            case "$arg" in
                -*|create|mirror|raidz2) continue ;;
                *=*) continue ;;
                /dev/*) continue ;;
                *) pool="$arg"; break ;;
            esac
        done
        [[ -n "$pool" ]] && { mkdir -p "$TEST_DIR/pools"; touch "$TEST_DIR/pools/$pool"; }
        exit 0
        ;;
    status) exit 0 ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$STUB_BIN/zpool"

    # zfs stub: distinguish the existence check (`-H -o name <ds>`) from
    # plain display calls — the former is the idempotency probe, the latter
    # is cosmetic and must not abort the script.
    cat > "$STUB_BIN/zfs" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$TEST_DIR/zfs.calls"
case "$1" in
    list)
        if [[ "$*" == *"-H"* ]]; then
            ds="${@: -1}"
            [[ -f "$TEST_DIR/datasets/$ds" ]] && exit 0
            exit 1
        fi
        exit 0
        ;;
    create)
        ds="$2"
        mkdir -p "$TEST_DIR/datasets/$(dirname "$ds")"
        touch "$TEST_DIR/datasets/$ds"
        exit 0
        ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$STUB_BIN/zfs"

    # Default drives.json — 4 + 2 valid.
    SCRIPT_DIR="$TEST_DIR/setup"
    mkdir -p "$SCRIPT_DIR"
    cp "$SRC_SCRIPT" "$SCRIPT_DIR/phase4-drives.sh"
    chmod +x "$SCRIPT_DIR/phase4-drives.sh"

    cat > "$SCRIPT_DIR/drives.json" <<'EOF'
{
  "media_pool": {
    "layout": "raidz2",
    "devices": [
      "/dev/disk/by-id/ata-A",
      "/dev/disk/by-id/ata-B",
      "/dev/disk/by-id/ata-C",
      "/dev/disk/by-id/ata-D"
    ]
  },
  "personal_pool": {
    "layout": "mirror",
    "devices": [
      "/dev/disk/by-id/ata-E",
      "/dev/disk/by-id/ata-F"
    ]
  }
}
EOF

    SCRIPT="$SCRIPT_DIR/phase4-drives.sh"
    # Redirect the absolute mount paths so chown/chmod don't need root.
    mkdir -p "$TEST_DIR/mnt" "$TEST_DIR/etc"
    : > "$TEST_DIR/etc/fstab"
    sed -i "s|/mnt/media|$TEST_DIR/mnt/media|g" "$SCRIPT"
    sed -i "s|/mnt/personal|$TEST_DIR/mnt/personal|g" "$SCRIPT"
    sed -i "s|/etc/fstab|$TEST_DIR/etc/fstab|g" "$SCRIPT"

    # ext4_drives provisioning needs blkid, findmnt, wipefs, mkfs.ext4,
    # systemctl, mount, and id. All record calls into TEST_DIR; default
    # behavior is "drive is empty / not mounted".
    cat > "$STUB_BIN/blkid" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$TEST_DIR/blkid.calls"
# Pre-formatted devices: a file with the device basename = TYPE\nUUID
dev="${@: -1}"
fixture="$TEST_DIR/blkid-fixtures/$(basename "$dev")"
if [[ -f "$fixture" ]]; then
    type=$(sed -n 1p "$fixture")
    uuid=$(sed -n 2p "$fixture")
    if [[ "$1" == "-s" && "$2" == "TYPE" ]]; then
        echo "$type"
    elif [[ "$1" == "-s" && "$2" == "UUID" ]]; then
        echo "$uuid"
    fi
    exit 0
fi
exit 2
EOF
    chmod +x "$STUB_BIN/blkid"

    make_stub findmnt 'echo "$*" >> "$TEST_DIR/findmnt.calls"; mnt="${@: -1}"; [[ -f "$TEST_DIR/mounted/$(basename "$mnt")" ]] && exit 0 || exit 1'
    make_stub wipefs
    make_stub mkfs.ext4 'echo "$*" >> "$TEST_DIR/mkfs.ext4.calls"; dev="${@: -1}"; mkdir -p "$TEST_DIR/blkid-fixtures"; printf "ext4\nfake-uuid-$$\n" > "$TEST_DIR/blkid-fixtures/$(basename "$dev")"'
    make_stub systemctl
    make_stub mount  'echo "$*" >> "$TEST_DIR/mount.calls"; mnt="${@: -1}"; [[ "$1" == "-a" ]] && true; mkdir -p "$TEST_DIR/mounted"; touch "$TEST_DIR/mounted/cache"'

    cat > "$STUB_BIN/id" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    -un) echo "tester" ;;
    -gn) echo "tester" ;;
    *) echo "tester:x:1000:1000::/home/tester:/bin/bash" ;;
esac
exit 0
EOF
    chmod +x "$STUB_BIN/id"
}

# Helper to add an ext4_drives entry to the existing drives.json fixture.
# The mountpoint goes straight into the JSON as a sandbox path so the
# script reads the redirected location at runtime — no script sed needed
# for the mountpoint. We do still sed the [[ -b $DEV ]] guard since the
# test fixture device path doesn't actually exist as a block device.
add_ext4_entry() {
    local device="$1" label="${2:-cache}"
    local subdirs="${3:-[\"huggingface\",\"scratch\"]}"
    local sandbox_mnt="$TEST_DIR/mnt/cache"
    jq --arg dev "$device" --arg mnt "$sandbox_mnt" --arg lbl "$label" \
       --argjson subs "$subdirs" \
       '.ext4_drives = [{device: $dev, mountpoint: $mnt, label: $lbl, subdirs: $subs, owner: "tester"}]' \
       "$SCRIPT_DIR/drives.json" > "$SCRIPT_DIR/drives.json.new"
    mv "$SCRIPT_DIR/drives.json.new" "$SCRIPT_DIR/drives.json"
    # The script's `[[ ! -b "$DEV" ]]` guard is meant to catch typos in
    # drives.json. Test devices are placeholder paths, not real block
    # devices, so neutralize the guard.
    sed -i 's|\[\[ ! -b "\$DEV" \]\]|false|g' "$SCRIPT"
}

teardown() {
    rm -rf "$TEST_DIR"
}

run_script() {
    yes yes | "$SCRIPT" 2>&1
}

# ---------------------------------------------------------------------------
# Preflight errors
# ---------------------------------------------------------------------------

@test "fails when drives.json is missing" {
    rm "$SCRIPT_DIR/drives.json"
    run run_script
    [ "$status" -ne 0 ]
    [[ "$output" == *"drives.json not found"* ]] || [[ "$output" == *"Run phase4-detect-drives.sh first"* ]]
}

@test "fails when jq is missing" {
    # PATH contains only $STUB_BIN → real jq is unreachable. We symlink
    # dirname/cat/bash into STUB_BIN so the script can start, but not jq.
    for cmd in bash cat dirname; do
        ln -sf "$(command -v $cmd)" "$STUB_BIN/$cmd"
    done
    SCRIPT_DIR="$SCRIPT_DIR" CONFIG="$SCRIPT_DIR/drives.json" PATH="$STUB_BIN" \
        run bash "$SCRIPT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"jq is required"* ]]
}

@test "fails when zpool is missing" {
    rm "$STUB_BIN/zpool"
    run run_script
    [ "$status" -ne 0 ]
    [[ "$output" == *"ZFS tools are required"* ]]
}

@test "fails when media_pool has wrong device count" {
    jq '.media_pool.devices = [.media_pool.devices[0], .media_pool.devices[1]]' \
        "$SCRIPT_DIR/drives.json" > "$SCRIPT_DIR/drives.json.new"
    mv "$SCRIPT_DIR/drives.json.new" "$SCRIPT_DIR/drives.json"
    run run_script
    [ "$status" -ne 0 ]
    [[ "$output" == *"media_pool must have exactly 4 devices"* ]]
}

@test "fails when personal_pool has wrong device count" {
    jq '.personal_pool.devices = [.personal_pool.devices[0]]' \
        "$SCRIPT_DIR/drives.json" > "$SCRIPT_DIR/drives.json.new"
    mv "$SCRIPT_DIR/drives.json.new" "$SCRIPT_DIR/drives.json"
    run run_script
    [ "$status" -ne 0 ]
    [[ "$output" == *"personal_pool must have exactly 2 devices"* ]]
}

# ---------------------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------------------

@test "creates both pools with correct layouts and devices" {
    run run_script
    [ "$status" -eq 0 ]
    # Two `zpool create` invocations total
    local creates
    creates=$(grep -c '^create ' "$TEST_DIR/zpool.calls" || true)
    [ "$creates" -eq 2 ]
    # Media pool uses raidz2 + 4 devices
    grep -E 'create .* media raidz2 /dev/disk/by-id/ata-A /dev/disk/by-id/ata-B /dev/disk/by-id/ata-C /dev/disk/by-id/ata-D' "$TEST_DIR/zpool.calls"
    # Personal pool uses mirror + 2 devices
    grep -E 'create .* personal mirror /dev/disk/by-id/ata-E /dev/disk/by-id/ata-F' "$TEST_DIR/zpool.calls"
}

@test "creates expected personal datasets" {
    run run_script
    [ "$status" -eq 0 ]
    grep -q 'create personal/photos'    "$TEST_DIR/zfs.calls"
    grep -q 'create personal/documents' "$TEST_DIR/zfs.calls"
    grep -q 'create personal/backups'   "$TEST_DIR/zfs.calls"
}

@test "does not create legacy plex01/plex02 datasets" {
    run run_script
    [ "$status" -eq 0 ]
    ! grep -q 'create media/plex01' "$TEST_DIR/zfs.calls"
    ! grep -q 'create media/plex02' "$TEST_DIR/zfs.calls"
}

@test "creates flat content subdirectories under /mnt/media" {
    run run_script
    [ "$status" -eq 0 ]
    for d in movies shows audiobooks downloads; do
        [ -d "$TEST_DIR/mnt/media/$d" ] || fail "missing /mnt/media/$d"
    done
    # No legacy plex01/plex02 split remains
    [ ! -d "$TEST_DIR/mnt/media/plex01" ]
    [ ! -d "$TEST_DIR/mnt/media/plex02" ]
}

@test "sets plex-ro read ACL on media directories" {
    run run_script
    [ "$status" -eq 0 ]
    # One non-default and one default ACL per media subtree
    grep -q 'g:plex-ro:rx' "$TEST_DIR/setfacl.calls"
    grep -q -- '-d' "$TEST_DIR/setfacl.calls"
}

@test "installs acl package" {
    run run_script
    [ "$status" -eq 0 ]
    grep -q 'install -y acl' "$TEST_DIR/apt.calls"
}

@test "creates missing service users" {
    # Empty the getent db → script will see all users as missing.
    : > "$TEST_DIR/getent.db"
    run run_script
    [ "$status" -eq 0 ]
    for u in plex immich minecraft qbittorrent audiobookshelf; do
        grep -q "^-r -s /sbin/nologin $u$" "$TEST_DIR/useradd.calls"
    done
}

@test "creates missing groups" {
    : > "$TEST_DIR/getent.db"
    run run_script
    [ "$status" -eq 0 ]
    for g in plex-rw plex-ro personal-rw personal-ro; do
        grep -q "^$g$" "$TEST_DIR/groupadd.calls"
    done
}

@test "adds users to their groups" {
    run run_script
    [ "$status" -eq 0 ]
    grep -q '\-aG plex-rw qbittorrent'    "$TEST_DIR/usermod.calls"
    grep -q '\-aG plex-ro plex'           "$TEST_DIR/usermod.calls"
    grep -q '\-aG plex-ro audiobookshelf' "$TEST_DIR/usermod.calls"
    grep -q '\-aG personal-rw immich'     "$TEST_DIR/usermod.calls"
}

# ---------------------------------------------------------------------------
# Idempotency
# ---------------------------------------------------------------------------

@test "skips pool creation when pool already exists" {
    mkdir -p "$TEST_DIR/pools"
    touch "$TEST_DIR/pools/media" "$TEST_DIR/pools/personal"
    run run_script
    [ "$status" -eq 0 ]
    [[ "$output" == *"media pool already exists"* ]]
    [[ "$output" == *"personal pool already exists"* ]]
    # No `create` calls
    ! grep -q '^create ' "$TEST_DIR/zpool.calls"
}

# ---------------------------------------------------------------------------
# ext4_drives provisioning
# ---------------------------------------------------------------------------

@test "skips ext4 phase when no ext4_drives in config" {
    run run_script
    [ "$status" -eq 0 ]
    [[ "$output" == *"No ext4_drives entries"* ]]
    [ ! -f "$TEST_DIR/mkfs.ext4.calls" ]
}

@test "formats and mounts a fresh ext4 drive" {
    add_ext4_entry "/dev/disk/by-id/ata-FAKE-CACHE"
    run run_script
    [ "$status" -eq 0 ]
    # mkfs.ext4 was called with the configured label
    grep -q '\-L cache /dev/disk/by-id/ata-FAKE-CACHE' "$TEST_DIR/mkfs.ext4.calls"
    # fstab gained the new entry
    grep -q "$TEST_DIR/mnt/cache  ext4" "$TEST_DIR/etc/fstab"
    # Subdirs created
    [ -d "$TEST_DIR/mnt/cache/huggingface" ]
    [ -d "$TEST_DIR/mnt/cache/scratch" ]
}

@test "preserves existing ext4 filesystem and does not reformat" {
    add_ext4_entry "/dev/disk/by-id/ata-FAKE-CACHE"
    # Pre-seed the fixture so blkid reports ext4 + UUID immediately.
    mkdir -p "$TEST_DIR/blkid-fixtures"
    printf "ext4\nexisting-uuid\n" > "$TEST_DIR/blkid-fixtures/ata-FAKE-CACHE"
    run run_script
    [ "$status" -eq 0 ]
    [[ "$output" == *"Existing ext4"* ]]
    [ ! -f "$TEST_DIR/mkfs.ext4.calls" ]
    grep -q "UUID=existing-uuid" "$TEST_DIR/etc/fstab"
}

@test "skips ext4 work when mountpoint already mounted" {
    add_ext4_entry "/dev/disk/by-id/ata-FAKE-CACHE"
    mkdir -p "$TEST_DIR/mounted"
    touch "$TEST_DIR/mounted/cache"
    run run_script
    [ "$status" -eq 0 ]
    [[ "$output" == *"already mounted"* ]]
    [ ! -f "$TEST_DIR/mkfs.ext4.calls" ]
}

@test "skips dataset creation when dataset already exists" {
    mkdir -p "$TEST_DIR/datasets/personal"
    touch "$TEST_DIR/datasets/personal/photos" \
          "$TEST_DIR/datasets/personal/documents" \
          "$TEST_DIR/datasets/personal/backups"
    run run_script
    [ "$status" -eq 0 ]
    # No `create` calls in zfs.calls
    ! grep -q '^create ' "$TEST_DIR/zfs.calls"
}
