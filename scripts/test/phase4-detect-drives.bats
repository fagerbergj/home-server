#!/usr/bin/env bats
# Tests for scripts/setup/phase4-detect-drives.sh

load 'test_helper.bash'

SRC_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../setup" && pwd)/phase4-detect-drives.sh"

setup() {
    TEST_DIR="$(mktemp -d)"
    export TEST_DIR
    stub_bin_init
    make_sudo_stub

    mkdir -p "$TEST_DIR/dev" "$TEST_DIR/by-id"

    # Fake OS drive (sda). The rest of the disks will be populated per-test.
    touch "$TEST_DIR/dev/sda"

    # findmnt stub — `findmnt -n -o SOURCE /` → root device
    make_stub findmnt 'echo "/dev/sda1"'

    # Copy script into the sandbox and redirect its hard-coded /dev paths
    # into our TEST_DIR tree.
    SCRIPT="$TEST_DIR/phase4-detect-drives.sh"
    cp "$SRC_SCRIPT" "$SCRIPT"
    sed -i "s|/dev/disk/by-id/ata-\\*|$TEST_DIR/by-id/ata-*|g" "$SCRIPT"
    sed -i "s|\"/dev/\\\$dev\"|\"$TEST_DIR/dev/\$dev\"|g" "$SCRIPT"
    # ↑ both in `readlink` comparison and in the fallback-by_id assignment
    chmod +x "$SCRIPT"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# make_disk <name> <size_gb> — create fake /dev/<name> + by-id symlink
make_disk() {
    local name="$1" size_gb="$2"
    touch "$TEST_DIR/dev/$name"
    ln -sf "$TEST_DIR/dev/$name" "$TEST_DIR/by-id/ata-MODEL-${name}-SERIAL"
}

# Writes an lsblk stub that handles both modes used by the script:
#   lsblk -no pkname <source>      → strip "/dev/" + trailing digits
#   lsblk -d -b -n -o NAME,SIZE,TYPE → disk listing from $TEST_DIR/lsblk.disks
make_lsblk_stub() {
    cat > "$STUB_BIN/lsblk" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$TEST_DIR/lsblk.calls"
# pkname mode
if [[ "$1" == "-no" && "$2" == "pkname" ]]; then
    src="$3"
    base="${src##*/}"
    base="${base%%[0-9]*}"
    echo "$base"
    exit 0
fi
# disk listing mode: -d -b -n -o NAME,SIZE,TYPE
if [[ "$*" == *"NAME,SIZE,TYPE"* ]]; then
    cat "$TEST_DIR/lsblk.disks"
    exit 0
fi
echo "lsblk: unexpected args: $*" >&2
exit 1
EOF
    chmod +x "$STUB_BIN/lsblk"
}

# 1GB = 10^9 bytes (base-10 as the script assumes)
gb_bytes() { echo $(( $1 * 1000 * 1000 * 1000 )); }

# ---------------------------------------------------------------------------
# Success path
# ---------------------------------------------------------------------------

@test "writes correct schema with 4× 26TB media + 2× 8TB personal" {
    make_lsblk_stub
    for d in sdb sdc sdd sde; do make_disk "$d" 26000; done
    for d in sdf sdg;          do make_disk "$d" 8000;  done

    {
        echo "sda  $(gb_bytes 500) disk"   # OS — must be excluded
        echo "sdb  $(gb_bytes 26000) disk"
        echo "sdc  $(gb_bytes 26000) disk"
        echo "sdd  $(gb_bytes 26000) disk"
        echo "sde  $(gb_bytes 26000) disk"
        echo "sdf  $(gb_bytes 8000) disk"
        echo "sdg  $(gb_bytes 8000) disk"
    } > "$TEST_DIR/lsblk.disks"

    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [ -f "$TEST_DIR/drives.json" ]

    # jq must parse it and match the expected shape
    run jq -r '.media_pool.layout' "$TEST_DIR/drives.json"
    [ "$output" = "raidz2" ]
    run jq -r '.personal_pool.layout' "$TEST_DIR/drives.json"
    [ "$output" = "mirror" ]
    run jq -r '.media_pool.devices | length' "$TEST_DIR/drives.json"
    [ "$output" = "4" ]
    run jq -r '.personal_pool.devices | length' "$TEST_DIR/drives.json"
    [ "$output" = "2" ]
}

@test "resolves /dev/sdX to by-id/ata-* paths" {
    make_lsblk_stub
    for d in sdb sdc sdd sde; do make_disk "$d" 26000; done
    for d in sdf sdg;          do make_disk "$d" 8000;  done
    {
        echo "sda  $(gb_bytes 500) disk"
        echo "sdb  $(gb_bytes 26000) disk"
        echo "sdc  $(gb_bytes 26000) disk"
        echo "sdd  $(gb_bytes 26000) disk"
        echo "sde  $(gb_bytes 26000) disk"
        echo "sdf  $(gb_bytes 8000) disk"
        echo "sdg  $(gb_bytes 8000) disk"
    } > "$TEST_DIR/lsblk.disks"

    run "$SCRIPT"
    [ "$status" -eq 0 ]

    # Every device entry must point at one of our ata-* symlinks.
    run jq -r '.media_pool.devices[], .personal_pool.devices[]' "$TEST_DIR/drives.json"
    for line in $output; do
        [[ "$line" == *"/by-id/ata-MODEL-"* ]] || fail "not by-id path: $line"
    done
}

@test "excludes the OS drive from detection" {
    make_lsblk_stub
    # Only 4 media + 2 personal disks beyond sda should count.
    for d in sdb sdc sdd sde; do make_disk "$d" 26000; done
    for d in sdf sdg;          do make_disk "$d" 8000;  done
    {
        echo "sda  $(gb_bytes 26000) disk"  # decoy: same size as media
        echo "sdb  $(gb_bytes 26000) disk"
        echo "sdc  $(gb_bytes 26000) disk"
        echo "sdd  $(gb_bytes 26000) disk"
        echo "sde  $(gb_bytes 26000) disk"
        echo "sdf  $(gb_bytes 8000) disk"
        echo "sdg  $(gb_bytes 8000) disk"
    } > "$TEST_DIR/lsblk.disks"

    run "$SCRIPT"
    [ "$status" -eq 0 ]
    run jq -r '.media_pool.devices | length' "$TEST_DIR/drives.json"
    [ "$output" = "4" ]
    run grep -c "sda" "$TEST_DIR/drives.json"
    [ "$output" = "0" ]
}

@test "ignores partitions and loop devices" {
    make_lsblk_stub
    for d in sdb sdc sdd sde; do make_disk "$d" 26000; done
    for d in sdf sdg;          do make_disk "$d" 8000;  done
    {
        echo "sda  $(gb_bytes 500) disk"
        echo "sda1 $(gb_bytes 500) part"     # partition
        echo "loop0 $(gb_bytes 1) loop"     # loop device
        echo "sdb  $(gb_bytes 26000) disk"
        echo "sdc  $(gb_bytes 26000) disk"
        echo "sdd  $(gb_bytes 26000) disk"
        echo "sde  $(gb_bytes 26000) disk"
        echo "sdf  $(gb_bytes 8000) disk"
        echo "sdg  $(gb_bytes 8000) disk"
    } > "$TEST_DIR/lsblk.disks"

    run "$SCRIPT"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# DRYRUN
# ---------------------------------------------------------------------------

@test "DRYRUN=1 skips writing drives.json" {
    make_lsblk_stub
    for d in sdb sdc sdd sde; do make_disk "$d" 26000; done
    for d in sdf sdg;          do make_disk "$d" 8000;  done
    {
        echo "sda  $(gb_bytes 500) disk"
        echo "sdb  $(gb_bytes 26000) disk"
        echo "sdc  $(gb_bytes 26000) disk"
        echo "sdd  $(gb_bytes 26000) disk"
        echo "sde  $(gb_bytes 26000) disk"
        echo "sdf  $(gb_bytes 8000) disk"
        echo "sdg  $(gb_bytes 8000) disk"
    } > "$TEST_DIR/lsblk.disks"

    DRYRUN=1 run "$SCRIPT"
    [ "$status" -eq 0 ]
    [ ! -f "$TEST_DIR/drives.json" ]
    [[ "$output" == *"DRYRUN=1"* ]]
}

# ---------------------------------------------------------------------------
# Failure: wrong counts still write but exit non-zero
# ---------------------------------------------------------------------------

@test "fewer than 4 media drives → non-zero exit but file still written" {
    make_lsblk_stub
    for d in sdb sdc sdd;      do make_disk "$d" 26000; done
    for d in sdf sdg;          do make_disk "$d" 8000;  done
    {
        echo "sda  $(gb_bytes 500) disk"
        echo "sdb  $(gb_bytes 26000) disk"
        echo "sdc  $(gb_bytes 26000) disk"
        echo "sdd  $(gb_bytes 26000) disk"
        echo "sdf  $(gb_bytes 8000) disk"
        echo "sdg  $(gb_bytes 8000) disk"
    } > "$TEST_DIR/lsblk.disks"

    run "$SCRIPT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"expected 4 media_pool drives"* ]]
    [ -f "$TEST_DIR/drives.json" ]
}

@test "fewer than 2 personal drives → non-zero exit but file still written" {
    make_lsblk_stub
    for d in sdb sdc sdd sde; do make_disk "$d" 26000; done
    make_disk sdf 8000
    {
        echo "sda  $(gb_bytes 500) disk"
        echo "sdb  $(gb_bytes 26000) disk"
        echo "sdc  $(gb_bytes 26000) disk"
        echo "sdd  $(gb_bytes 26000) disk"
        echo "sde  $(gb_bytes 26000) disk"
        echo "sdf  $(gb_bytes 8000) disk"
    } > "$TEST_DIR/lsblk.disks"

    run "$SCRIPT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"expected 2 personal_pool drives"* ]]
    [ -f "$TEST_DIR/drives.json" ]
}

@test "drives outside both size buckets are reported as unassigned" {
    make_lsblk_stub
    for d in sdb sdc sdd sde; do make_disk "$d" 26000; done
    for d in sdf sdg;          do make_disk "$d" 8000;  done
    make_disk sdh 4000                      # oddball 4TB — neither bucket
    {
        echo "sda  $(gb_bytes 500) disk"
        echo "sdb  $(gb_bytes 26000) disk"
        echo "sdc  $(gb_bytes 26000) disk"
        echo "sdd  $(gb_bytes 26000) disk"
        echo "sde  $(gb_bytes 26000) disk"
        echo "sdf  $(gb_bytes 8000) disk"
        echo "sdg  $(gb_bytes 8000) disk"
        echo "sdh  $(gb_bytes 4000) disk"
    } > "$TEST_DIR/lsblk.disks"

    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Unassigned drives"* ]]
    [[ "$output" == *"sdh"* ]]
}
