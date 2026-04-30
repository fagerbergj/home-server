#!/usr/bin/env bats
# Tests for scripts/setup/phase4-alerts.sh

load 'test_helper.bash'

SRC_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../setup" && pwd)/phase4-alerts.sh"

setup() {
    TEST_DIR="$(mktemp -d)"
    export TEST_DIR
    stub_bin_init
    make_sudo_stub

    make_stub apt
    make_stub systemctl
    make_stub msmtp
    make_stub zpool           # `zpool events -c` inside the smoke-test
    make_stub zed             # `zed -M`

    # tee stub — respects `-a` and real file paths.
    cat > "$STUB_BIN/tee" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$TEST_DIR/tee.calls"
exec /usr/bin/tee "$@"
EOF
    chmod +x "$STUB_BIN/tee"

    # crontab stub reads/writes $TEST_DIR/crontab
    cat > "$STUB_BIN/crontab" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$TEST_DIR/crontab.calls"
if [[ "$1" == "-l" ]]; then
    cat "$TEST_DIR/crontab" 2>/dev/null
    # Exit 1 if empty, matching real crontab behavior
    [[ -s "$TEST_DIR/crontab" ]] || exit 1
    exit 0
fi
# Writing: stdin → file
cat > "$TEST_DIR/crontab"
EOF
    chmod +x "$STUB_BIN/crontab"

    # Fake /etc/zfs hierarchy the script writes into.
    mkdir -p "$TEST_DIR/etc/zfs/zed.d"

    # Repo layout: scripts/check-disk.sh sibling + scripts/setup/phase4-alerts.sh
    REPO_ROOT="$TEST_DIR/repo"
    mkdir -p "$REPO_ROOT/scripts/setup"
    touch "$REPO_ROOT/scripts/check-disk.sh"
    chmod +x "$REPO_ROOT/scripts/check-disk.sh"

    SCRIPT="$REPO_ROOT/scripts/setup/phase4-alerts.sh"
    cp "$SRC_SCRIPT" "$SCRIPT"
    # Point the zed.rc write at our sandbox /etc.
    sed -i "s|/etc/zfs/zed.d/zed.rc|$TEST_DIR/etc/zfs/zed.d/zed.rc|g" "$SCRIPT"
    chmod +x "$SCRIPT"

    export HOME="$TEST_DIR/home"
    mkdir -p "$HOME"

    export GMAIL_APP_PASSWORD="testpw"
    export REPO_ROOT
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Package install
# ---------------------------------------------------------------------------

@test "installs msmtp, msmtp-mta, and zfs-zed" {
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -q 'install -y msmtp msmtp-mta zfs-zed' "$TEST_DIR/apt.calls"
}

# ---------------------------------------------------------------------------
# msmtp
# ---------------------------------------------------------------------------

@test "writes ~/.msmtprc with gmail account" {
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [ -f "$HOME/.msmtprc" ]
    grep -q 'host *smtp.gmail.com'              "$HOME/.msmtprc"
    grep -q 'user *jf.fagerberg@gmail.com'      "$HOME/.msmtprc"
    grep -q 'password *testpw'                  "$HOME/.msmtprc"
}

@test "~/.msmtprc is mode 600" {
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    local mode
    mode=$(stat -c '%a' "$HOME/.msmtprc")
    [ "$mode" = "600" ]
}

# ---------------------------------------------------------------------------
# ZED
# ---------------------------------------------------------------------------

@test "writes zed.rc with email knobs" {
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [ -f "$TEST_DIR/etc/zfs/zed.d/zed.rc" ]
    grep -q 'ZED_EMAIL_ADDR="jf.fagerberg@gmail.com"' "$TEST_DIR/etc/zfs/zed.d/zed.rc"
    grep -q 'ZED_EMAIL_PROG="msmtp"'                   "$TEST_DIR/etc/zfs/zed.d/zed.rc"
    grep -q 'ZED_NOTIFY_VERBOSE=1'                     "$TEST_DIR/etc/zfs/zed.d/zed.rc"
}

@test "enables zed systemd unit" {
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    # Must use the real unit name, not the `zed.service` alias — Ubuntu
    # systemctl refuses to enable aliased/linked unit names.
    grep -q 'enable --now zfs-zed.service' "$TEST_DIR/systemctl.calls"
}

# ---------------------------------------------------------------------------
# Cron
# ---------------------------------------------------------------------------

@test "installs disk-usage cron pointing at check-disk.sh" {
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [ -f "$TEST_DIR/crontab" ]
    grep -q '0 8 \* \* \*.*scripts/check-disk.sh' "$TEST_DIR/crontab"
}

@test "does not duplicate existing cron entry" {
    # Pre-seed a crontab already containing check-disk.sh.
    echo "0 8 * * * $REPO_ROOT/scripts/check-disk.sh" > "$TEST_DIR/crontab"
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    local count
    count=$(grep -c check-disk.sh "$TEST_DIR/crontab")
    [ "$count" -eq 1 ]
}
