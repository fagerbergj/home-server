#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../phase4-alerts.sh"

setup() {
    export TMPDIR="$(mktemp -d)"
    export PATH="$TMPDIR/bin:$PATH"
    mkdir -p "$TMPDIR/bin"

    for cmd in sudo apt mdadm; do
        cat > "$TMPDIR/bin/$cmd" <<EOF
#!/bin/bash
echo "$cmd called with: \$*"
EOF
        chmod +x "$TMPDIR/bin/$cmd"
    done

    # Mock crontab — record calls and return empty list
    cat > "$TMPDIR/bin/crontab" <<'EOF'
#!/bin/bash
if [[ "$1" == "-l" ]]; then
    echo ""
else
    echo "crontab called with: $*"
    cat > /dev/null
fi
EOF
    chmod +x "$TMPDIR/bin/crontab"

    # Mock realpath
    cat > "$TMPDIR/bin/realpath" <<'EOF'
#!/bin/bash
echo "/scripts/check-disk.sh"
EOF
    chmod +x "$TMPDIR/bin/realpath"

    # Fake mdadm.conf so MAILADDR check doesn't fail
    export MDADM_CONF="$TMPDIR/mdadm.conf"
    touch "$MDADM_CONF"

    # Provide a password via stdin
    export TEST_PASSWORD="test-app-password"
}

teardown() {
    rm -rf "$TMPDIR"
    rm -f ~/.msmtprc
}

@test "installs msmtp" {
    run bash "$SCRIPT" <<< "$TEST_PASSWORD"
    [[ "$output" == *"msmtp"* ]]
}

@test "writes ~/.msmtprc" {
    bash "$SCRIPT" <<< "$TEST_PASSWORD" || true
    [[ -f ~/.msmtprc ]]
}

@test "sets restrictive permissions on ~/.msmtprc" {
    bash "$SCRIPT" <<< "$TEST_PASSWORD" || true
    perms=$(stat -c "%a" ~/.msmtprc)
    [[ "$perms" == "600" ]]
}

@test "configures smtp.gmail.com" {
    bash "$SCRIPT" <<< "$TEST_PASSWORD" || true
    grep -q "smtp.gmail.com" ~/.msmtprc
}

@test "adds disk usage cron job" {
    run bash "$SCRIPT" <<< "$TEST_PASSWORD"
    [[ "$output" == *"crontab"* ]]
}

@test "runs mdadm monitor test" {
    run bash "$SCRIPT" <<< "$TEST_PASSWORD"
    [[ "$output" == *"--monitor"* ]]
}
