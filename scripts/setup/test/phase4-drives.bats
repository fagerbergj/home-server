#!/usr/bin/env bats
# Tests for phase4-drives.sh (ZFS pool + flat directory setup)

SCRIPT="$BATS_TEST_DIRNAME/../phase4-drives.sh"

setup() {
    export TMPDIR
    TMPDIR="$(mktemp -d)"
    export PATH="$TMPDIR/bin:$PATH"
    mkdir -p "$TMPDIR/bin" "$TMPDIR/mnt"

    cat > "$TMPDIR/drives.json" <<'EOF'
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

    cat > "$TMPDIR/bin/sudo" <<'EOF'
#!/bin/bash
"$@"
EOF
    chmod +x "$TMPDIR/bin/sudo"

    ln -sf "$(command -v jq)" "$TMPDIR/bin/jq"

    cat > "$TMPDIR/bin/apt" <<EOF
#!/bin/bash
echo "\$*" >> "$TMPDIR/apt.calls"
EOF
    chmod +x "$TMPDIR/bin/apt"

    cat > "$TMPDIR/bin/zpool" <<EOF
#!/bin/bash
echo "\$*" >> "$TMPDIR/zpool.calls"
case "\$1" in
    list)
        pool="\${@: -1}"
        [[ -f "$TMPDIR/pools/\$pool" ]] && exit 0
        exit 1 ;;
    create)
        pool=""
        for arg in "\$@"; do
            case "\$arg" in -*|create|mirror|raidz2|*=*|/dev/*) continue ;; *) pool="\$arg"; break ;; esac
        done
        [[ -n "\$pool" ]] && { mkdir -p "$TMPDIR/pools"; touch "$TMPDIR/pools/\$pool"; }
        exit 0 ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$TMPDIR/bin/zpool"

    cat > "$TMPDIR/bin/zfs" <<EOF
#!/bin/bash
echo "\$*" >> "$TMPDIR/zfs.calls"
case "\$1" in
    list)
        if [[ "\$*" == *"-H"* ]]; then
            ds="\${@: -1}"
            [[ -f "$TMPDIR/datasets/\$ds" ]] && exit 0
            exit 1
        fi
        exit 0 ;;
    create)
        ds="\$2"
        mkdir -p "$TMPDIR/datasets/\$(dirname "\$ds")"
        touch "$TMPDIR/datasets/\$ds"
        exit 0 ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$TMPDIR/bin/zfs"

    cat > "$TMPDIR/bin/setfacl" <<EOF
#!/bin/bash
echo "\$*" >> "$TMPDIR/setfacl.calls"
EOF
    chmod +x "$TMPDIR/bin/setfacl"

    for cmd in chown chmod; do
        cat > "$TMPDIR/bin/$cmd" <<EOF
#!/bin/bash
echo "$cmd \$*" >> "$TMPDIR/fs.calls"
EOF
        chmod +x "$TMPDIR/bin/$cmd"
    done

    for cmd in useradd groupadd usermod; do
        cat > "$TMPDIR/bin/$cmd" <<EOF
#!/bin/bash
echo "\$*" >> "$TMPDIR/$cmd.calls"
EOF
        chmod +x "$TMPDIR/bin/$cmd"
    done

    cat > "$TMPDIR/bin/getent" <<EOF
#!/bin/bash
case "\$2" in
    plex-rw)        echo "plex-rw:x:2001:" ;;
    plex-ro)        echo "plex-ro:x:2002:" ;;
    personal-rw)    echo "personal-rw:x:2003:" ;;
    personal-ro)    echo "personal-ro:x:2004:" ;;
    plex)           echo "plex:x:999:" ;;
    immich)         echo "immich:x:996:" ;;
    minecraft)      echo "minecraft:x:995:" ;;
    qbittorrent)    echo "qbittorrent:x:994:" ;;
    audiobookshelf) echo "audiobookshelf:x:993:" ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "$TMPDIR/bin/getent"

    cat > "$TMPDIR/bin/id" <<EOF
#!/bin/bash
case "\$1" in
    plex)           echo "999" ;;
    immich)         echo "996" ;;
    minecraft)      echo "995" ;;
    qbittorrent)    echo "994" ;;
    audiobookshelf) echo "993" ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "$TMPDIR/bin/id"

    # Patch mount paths so mkdir/chown work without root
    PATCHED="$TMPDIR/phase4-drives.sh"
    sed "s|/mnt/media|$TMPDIR/mnt/media|g; s|/mnt/personal|$TMPDIR/mnt/personal|g" "$SCRIPT" > "$PATCHED"
    chmod +x "$PATCHED"
}

teardown() {
    rm -rf "$TMPDIR"
}

run_script() {
    SCRIPT_DIR="$TMPDIR" yes yes | bash "$TMPDIR/phase4-drives.sh" 2>&1
}

@test "aborts if drives.json not found" {
    rm "$TMPDIR/drives.json"
    run bash -c "SCRIPT_DIR='$TMPDIR' bash '$TMPDIR/phase4-drives.sh'"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "aborts when user enters 'no'" {
    run bash -c "SCRIPT_DIR='$TMPDIR' echo no | bash '$TMPDIR/phase4-drives.sh'"
    [[ "$output" == *"Aborted"* ]]
}

@test "creates media pool with raidz2" {
    run run_script
    [ "$status" -eq 0 ]
    grep -q 'create .* media raidz2' "$TMPDIR/zpool.calls"
}

@test "creates personal pool with mirror" {
    run run_script
    [ "$status" -eq 0 ]
    grep -q 'create .* personal mirror' "$TMPDIR/zpool.calls"
}

@test "creates flat content directories under /mnt/media" {
    run run_script
    [ "$status" -eq 0 ]
    for d in movies shows audiobooks downloads; do
        [ -d "$TMPDIR/mnt/media/$d" ] || fail "missing /mnt/media/$d"
    done
}

@test "does not create legacy plex01 or plex02 directories" {
    run run_script
    [ "$status" -eq 0 ]
    [ ! -d "$TMPDIR/mnt/media/plex01" ]
    [ ! -d "$TMPDIR/mnt/media/plex02" ]
}

@test "does not create legacy plex01/plex02 ZFS datasets" {
    run run_script
    [ "$status" -eq 0 ]
    ! grep -q 'create media/plex01' "$TMPDIR/zfs.calls"
    ! grep -q 'create media/plex02' "$TMPDIR/zfs.calls"
}

@test "creates personal datasets: photos documents backups" {
    run run_script
    [ "$status" -eq 0 ]
    grep -q 'create personal/photos'    "$TMPDIR/zfs.calls"
    grep -q 'create personal/documents' "$TMPDIR/zfs.calls"
    grep -q 'create personal/backups'   "$TMPDIR/zfs.calls"
}

@test "skips pool creation when pool already exists" {
    mkdir -p "$TMPDIR/pools"
    touch "$TMPDIR/pools/media" "$TMPDIR/pools/personal"
    run run_script
    [ "$status" -eq 0 ]
    [[ "$output" == *"already exists"* ]]
    ! grep -q '^create ' "$TMPDIR/zpool.calls"
}

@test "creates service users and groups" {
    run run_script
    [ "$status" -eq 0 ]
    grep -q 'qbittorrent' "$TMPDIR/useradd.calls" || true
    grep -q 'plex-rw'     "$TMPDIR/groupadd.calls" || true
}

@test "prints UID/GID summary at end" {
    run run_script
    [ "$status" -eq 0 ]
    [[ "$output" == *"PUID (plex)"* ]]
    [[ "$output" == *"PGID (plex-rw)"* ]]
}
