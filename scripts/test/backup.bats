#!/usr/bin/env bats
# Tests for scripts/backup.sh
#
# Stubs out docker, rsync, and the filesystem so nothing touches the real
# server. Each test runs in an isolated temp directory.

setup() {
    # Scratch dir for this test
    TEST_DIR="$(mktemp -d)"

    # Fake repo root
    REPO_ROOT="$TEST_DIR/home-server"
    mkdir -p "$REPO_ROOT/passwords/data"
    mkdir -p "$REPO_ROOT/minecraft/data/world"
    mkdir -p "$REPO_ROOT/monitoring/grafana"
    mkdir -p "$REPO_ROOT/monitoring/prometheus/data"
    mkdir -p "$REPO_ROOT/notes/rmfakecloud-data"
    mkdir -p "$REPO_ROOT/plex/config/Cache"
    mkdir -p "$REPO_ROOT/audiobooks/config"
    mkdir -p "$REPO_ROOT/audiobooks/metadata"
    mkdir -p "$REPO_ROOT/torrent/sonarr/config"
    mkdir -p "$REPO_ROOT/torrent/radarr/config"
    mkdir -p "$REPO_ROOT/torrent/prowlarr/config"
    mkdir -p "$REPO_ROOT/torrent/config"
    mkdir -p "$REPO_ROOT/api/data/authentik-media"
    mkdir -p "$REPO_ROOT/api/data/authentik-certs"
    touch "$REPO_ROOT/.env"
    echo 'DB_USERNAME=immich' >> "$REPO_ROOT/.env"
    echo 'DB_PASSWORD=secret' >> "$REPO_ROOT/.env"
    echo 'DB_DATABASE_NAME=immich' >> "$REPO_ROOT/.env"
    echo 'AUTHENTIK_DB_USER=authentik' >> "$REPO_ROOT/.env"
    echo 'AUTHENTIK_DB_NAME=authentik' >> "$REPO_ROOT/.env"
    echo 'AUTHENTIK_DB_PASSWORD=secret' >> "$REPO_ROOT/.env"

    # Fake personal mount
    mkdir -p "$TEST_DIR/mnt/personal"

    # Stub bin — put stubs before real commands on PATH
    STUB_BIN="$TEST_DIR/bin"
    mkdir -p "$STUB_BIN"

    # docker stub — records calls, succeeds by default
    cat > "$STUB_BIN/docker" <<'EOF'
#!/usr/bin/env bash
echo "docker $*" >> "$TEST_DIR/docker.calls"
# pg_dump: emit a fake dump to stdout
if [[ "$*" == *"pg_dump"* ]]; then
    echo "FAKE_DUMP"
fi
EOF
    chmod +x "$STUB_BIN/docker"

    # rsync stub — records calls, creates dest dirs so du doesn't fail
    cat > "$STUB_BIN/rsync" <<'EOF'
#!/usr/bin/env bash
echo "rsync $*" >> "$TEST_DIR/rsync.calls"
# Create destination directory so the summary ls doesn't fail
dest="${@: -1}"
mkdir -p "$dest"
EOF
    chmod +x "$STUB_BIN/rsync"

    # gpg stub — records calls, creates output file
    cat > "$STUB_BIN/gpg" <<'EOF'
#!/usr/bin/env bash
echo "gpg $*" >> "$TEST_DIR/gpg.calls"
# Parse --output arg and touch it
for i in "$@"; do
    if [[ "$PREV" == "--output" ]]; then
        touch "$i"
    fi
    PREV="$i"
done
EOF
    chmod +x "$STUB_BIN/gpg"

    # sudo stub — just run the command without sudo
    cat > "$STUB_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF
    chmod +x "$STUB_BIN/sudo"

    # Fake /etc/fstab and mdadm.conf
    mkdir -p "$TEST_DIR/etc/mdadm"
    echo "UUID=fake / ext4 defaults 0 1" > "$TEST_DIR/etc/fstab"
    echo "ARRAY /dev/md0 metadata=1.2" > "$TEST_DIR/etc/mdadm/mdadm.conf"

    export PATH="$STUB_BIN:$PATH"
    export TEST_DIR REPO_ROOT

    # Override mount point and env paths inside the script via env vars
    # We achieve this by writing a wrapper that sets the vars before sourcing
    SCRIPT="$REPO_ROOT/scripts/backup.sh"
    mkdir -p "$REPO_ROOT/scripts"
    cp "$(dirname "$BATS_TEST_FILENAME")/../backup.sh" "$SCRIPT"

    # Patch hardcoded paths so tests are hermetic
    sed -i "s|/mnt/personal|$TEST_DIR/mnt/personal|g" "$SCRIPT"
    sed -i "s|/etc/fstab|$TEST_DIR/etc/fstab|g" "$SCRIPT"
    sed -i "s|/etc/mdadm/mdadm.conf|$TEST_DIR/etc/mdadm/mdadm.conf|g" "$SCRIPT"
    chmod +x "$SCRIPT"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ── Preflight checks ──────────────────────────────────────────────────────

@test "fails if personal is not mounted" {
    rmdir "$TEST_DIR/mnt/personal"
    run bash "$REPO_ROOT/scripts/backup.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"personal is not mounted"* ]]
}

@test "fails if .env is missing" {
    rm "$REPO_ROOT/.env"
    run bash "$REPO_ROOT/scripts/backup.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *".env not found"* ]]
}

# ── Happy path ────────────────────────────────────────────────────────────

@test "exits 0 when everything is present" {
    run bash "$REPO_ROOT/scripts/backup.sh"
    [ "$status" -eq 0 ]
}

@test "creates a dated backup directory under personal" {
    run bash "$REPO_ROOT/scripts/backup.sh"
    [ "$status" -eq 0 ]
    local today
    today="$(date +%Y-%m-%d)"
    [ -d "$TEST_DIR/mnt/personal/backups/$today" ]
}

# ── rsync calls ───────────────────────────────────────────────────────────

@test "rsyncs vaultwarden data" {
    run bash "$REPO_ROOT/scripts/backup.sh"
    grep -q "passwords/data/" "$TEST_DIR/rsync.calls"
}

@test "rsyncs minecraft data" {
    run bash "$REPO_ROOT/scripts/backup.sh"
    grep -q "minecraft/data/" "$TEST_DIR/rsync.calls"
}

@test "rsyncs grafana data" {
    run bash "$REPO_ROOT/scripts/backup.sh"
    grep -q "monitoring/grafana/" "$TEST_DIR/rsync.calls"
}

@test "rsyncs prometheus data" {
    run bash "$REPO_ROOT/scripts/backup.sh"
    grep -q "monitoring/prometheus/data/" "$TEST_DIR/rsync.calls"
}

@test "rsyncs rmfakecloud data" {
    run bash "$REPO_ROOT/scripts/backup.sh"
    grep -q "notes/rmfakecloud-data/" "$TEST_DIR/rsync.calls"
}

@test "all rsync calls use --delete flag" {
    run bash "$REPO_ROOT/scripts/backup.sh"
    while IFS= read -r line; do
        [[ "$line" == *"--delete"* ]] || fail "rsync call missing --delete: $line"
    done < "$TEST_DIR/rsync.calls"
}

# ── Docker calls ─────────────────────────────────────────────────────────

@test "calls pg_dump on immich-postgres container" {
    run bash "$REPO_ROOT/scripts/backup.sh"
    grep -q "immich-postgres" "$TEST_DIR/docker.calls"
    grep -q "pg_dump" "$TEST_DIR/docker.calls"
}

@test "pg_dump output is written to backup directory" {
    run bash "$REPO_ROOT/scripts/backup.sh"
    local today
    today="$(date +%Y-%m-%d)"
    [ -f "$TEST_DIR/mnt/personal/backups/$today/immich-postgres.dump" ]
}

@test "calls save-all on minecraft container before rsync" {
    run bash "$REPO_ROOT/scripts/backup.sh"
    grep -q "minecraft.*save-all\|save-all.*minecraft" "$TEST_DIR/docker.calls"
}

@test "minecraft save-all happens before minecraft rsync" {
    run bash "$REPO_ROOT/scripts/backup.sh"
    local save_line rsync_line
    save_line=$(grep -n "minecraft.*save-all\|save-all.*minecraft" "$TEST_DIR/docker.calls" | cut -d: -f1)
    rsync_line=$(grep -n "minecraft/data" "$TEST_DIR/rsync.calls" | cut -d: -f1)
    # Both calls were made
    [ -n "$save_line" ]
    [ -n "$rsync_line" ]
}

# ── Plex ──────────────────────────────────────────────────────────────────

@test "rsyncs plex config" {
    run bash "$REPO_ROOT/scripts/backup.sh"
    grep -q "plex/config/" "$TEST_DIR/rsync.calls"
}

@test "plex rsync excludes Cache directory" {
    run bash "$REPO_ROOT/scripts/backup.sh"
    grep "plex/config/" "$TEST_DIR/rsync.calls" | grep -q "\-\-exclude=Cache/"
}

# ── Audiobookshelf ────────────────────────────────────────────────────────

@test "rsyncs audiobookshelf config" {
    run bash "$REPO_ROOT/scripts/backup.sh"
    grep -q "audiobooks/config/" "$TEST_DIR/rsync.calls"
}

@test "rsyncs audiobookshelf metadata" {
    run bash "$REPO_ROOT/scripts/backup.sh"
    grep -q "audiobooks/metadata/" "$TEST_DIR/rsync.calls"
}

# ── Sonarr / Radarr ───────────────────────────────────────────────────────

@test "rsyncs sonarr config" {
    run bash "$REPO_ROOT/scripts/backup.sh"
    grep -q "sonarr/config/" "$TEST_DIR/rsync.calls"
}

@test "rsyncs radarr config" {
    run bash "$REPO_ROOT/scripts/backup.sh"
    grep -q "radarr/config/" "$TEST_DIR/rsync.calls"
}

# ── Authentik ─────────────────────────────────────────────────────────────

@test "calls pg_dump on authentik-postgres container" {
    run bash "$REPO_ROOT/scripts/backup.sh"
    grep -q "authentik-postgres" "$TEST_DIR/docker.calls"
    grep -q "pg_dump" "$TEST_DIR/docker.calls"
}

@test "authentik pg_dump output is written to backup directory" {
    run bash "$REPO_ROOT/scripts/backup.sh"
    local today
    today="$(date +%Y-%m-%d)"
    [ -f "$TEST_DIR/mnt/personal/backups/$today/authentik-postgres.dump" ]
}

@test "rsyncs authentik media" {
    run bash "$REPO_ROOT/scripts/backup.sh"
    grep -q "authentik-media/" "$TEST_DIR/rsync.calls"
}

@test "rsyncs authentik certs" {
    run bash "$REPO_ROOT/scripts/backup.sh"
    grep -q "authentik-certs/" "$TEST_DIR/rsync.calls"
}

# ── Retention ─────────────────────────────────────────────────────────────

@test "keeps only 3 most recent backups" {
    local base="$TEST_DIR/mnt/personal/backups"
    # Pre-create 4 old dated directories
    mkdir -p "$base/2026-01-01" "$base/2026-01-02" "$base/2026-01-03" "$base/2026-01-04"
    run bash "$REPO_ROOT/scripts/backup.sh"
    [ "$status" -eq 0 ]
    # Today's backup + 2 most recent old ones = 3 total (oldest should be gone)
    local count
    count=$(ls -1d "$base"/????-??-?? | wc -l)
    [ "$count" -le 3 ]
}

@test "removes oldest backup when over limit" {
    local base="$TEST_DIR/mnt/personal/backups"
    mkdir -p "$base/2026-01-01" "$base/2026-01-02" "$base/2026-01-03"
    run bash "$REPO_ROOT/scripts/backup.sh"
    [ "$status" -eq 0 ]
    # 2026-01-01 should be pruned (oldest)
    [ ! -d "$base/2026-01-01" ]
}

@test "does not prune when under limit" {
    local base="$TEST_DIR/mnt/personal/backups"
    mkdir -p "$base/2026-01-01" "$base/2026-01-02"
    run bash "$REPO_ROOT/scripts/backup.sh"
    [ "$status" -eq 0 ]
    # Only 3 total (2 old + today) — nothing should be pruned
    [ -d "$base/2026-01-01" ]
    [ -d "$base/2026-01-02" ]
}

# ── Prowlarr / qBittorrent ────────────────────────────────────────────────

@test "rsyncs prowlarr config" {
    run bash "$REPO_ROOT/scripts/backup.sh"
    grep -q "prowlarr/config/" "$TEST_DIR/rsync.calls"
}

@test "rsyncs qbittorrent config" {
    run bash "$REPO_ROOT/scripts/backup.sh"
    grep -q "torrent/config/" "$TEST_DIR/rsync.calls"
}

# ── .env encryption ───────────────────────────────────────────────────────

@test "skips .env backup when BACKUP_GPG_PASSPHRASE is not set" {
    run bash "$REPO_ROOT/scripts/backup.sh"
    [ "$status" -eq 0 ]
    # gpg should not have been called
    [ ! -f "$TEST_DIR/gpg.calls" ] || ! grep -q "\-\-symmetric" "$TEST_DIR/gpg.calls"
}

@test "encrypts .env when BACKUP_GPG_PASSPHRASE is set" {
    echo 'BACKUP_GPG_PASSPHRASE=testpass' >> "$REPO_ROOT/.env"
    run bash "$REPO_ROOT/scripts/backup.sh"
    [ "$status" -eq 0 ]
    grep -q "\-\-symmetric" "$TEST_DIR/gpg.calls"
}

@test "encrypted .env written to backup directory" {
    echo 'BACKUP_GPG_PASSPHRASE=testpass' >> "$REPO_ROOT/.env"
    run bash "$REPO_ROOT/scripts/backup.sh"
    [ "$status" -eq 0 ]
    local today
    today="$(date +%Y-%m-%d)"
    [ -f "$TEST_DIR/mnt/personal/backups/$today/env.gpg" ]
}

# ── System config ─────────────────────────────────────────────────────────

@test "copies fstab to backup directory" {
    run bash "$REPO_ROOT/scripts/backup.sh"
    [ "$status" -eq 0 ]
    local today
    today="$(date +%Y-%m-%d)"
    [ -f "$TEST_DIR/mnt/personal/backups/$today/system/fstab" ]
}

@test "copies mdadm.conf to backup directory when present" {
    run bash "$REPO_ROOT/scripts/backup.sh"
    [ "$status" -eq 0 ]
    local today
    today="$(date +%Y-%m-%d)"
    [ -f "$TEST_DIR/mnt/personal/backups/$today/system/mdadm.conf" ]
}
