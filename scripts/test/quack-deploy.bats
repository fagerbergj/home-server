#!/usr/bin/env bats
# Tests for quack/deploy.sh against a throwaway home-server clone whose origin is a bare repo.
# docker and curl are stubs: the GitHub API knows GREEN as the only green build, the registry gives every tag digest
# sha256:abc, the fake stack serves whatever sha the pin names unless it is BAD_SHA, and SMTP writes to mail.txt.

setup() {
    TEST_DIR="$(mktemp -d)"
    export TEST_DIR
    source "$BATS_TEST_DIRNAME/test_helper.bash"
    stub_bin_init
    SCRIPT="$BATS_TEST_DIRNAME/../../quack/deploy.sh"
    OLD=1111111111111111111111111111111111111111
    NEW=2222222222222222222222222222222222222222
    export GREEN="$NEW"

    git init -q --bare -b main "$TEST_DIR/remote.git"
    git init -q -b main "$TEST_DIR/hs"
    mkdir -p "$TEST_DIR/hs/quack" "$TEST_DIR/hs/updater"
    printf 'x-quack-v1-image: &quack-v1-image ghcr.io/fagerbergj/quack:v1-%s\nservices: {}\n' "$OLD" > "$TEST_DIR/hs/quack/docker-compose.yml"
    printf '      - WATCHTOWER_NOTIFICATION_EMAIL_%s\n' FROM=me@test TO=me@test SERVER=smtp.test SERVER_PORT=587 SERVER_USER=me@test \
        > "$TEST_DIR/hs/updater/docker-compose.yml"
    git -C "$TEST_DIR/hs" add -A
    git -C "$TEST_DIR/hs" -c user.name=t -c user.email=t@t commit -q -m init
    git -C "$TEST_DIR/hs" remote add origin "$TEST_DIR/remote.git"
    git -C "$TEST_DIR/hs" push -q origin HEAD:main
    echo 'GMAIL_APP_PASSWORD="app-password"' > "$TEST_DIR/hs/updater/.env"

    export HOME_SERVER_DIR="$TEST_DIR/hs" QUACK_RUNS_API=http://api.test/runs QUACK_DEPLOY_LOCK="$TEST_DIR/lock"
    export QUACK_HEALTH_SECONDS=0 QUACK_SETTLE_SECONDS=0 GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_EMAIL=t@t

    cat > "$STUB_BIN/docker" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$TEST_DIR/docker.calls"
case "$1 $2" in
  "buildx imagetools") echo sha256:abc ;;
  run*) echo "${VALIDATE_OUT:-13 loaded, 0 failed}" ;;
  inspect*) echo "true 0" ;;
  "compose up")
    sha=$(sed -nE 's/^x-quack-v1-image: .*:v1-([0-9a-f]{40}).*/\1/p' "$HOME_SERVER_DIR/quack/docker-compose.yml")
    [[ $sha == "${BAD_SHA:-}" ]] && sha=crashed
    echo "$sha" > "$TEST_DIR/serving" ;;
esac
EOF
    cat > "$STUB_BIN/curl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *api.test*per_page=1*) echo "{\"workflow_runs\":[{\"head_sha\":\"$GREEN\"}]}" ;;
  *api.test*head_sha=$GREEN*) echo '{"total_count":1}' ;;
  *api.test*) echo '{"total_count":0}' ;;
  *smtp://*) cat > "$TEST_DIR/mail.txt" ;;
  */version*) echo "{\"commit\":\"$(cat "$TEST_DIR/serving")\",\"builtAt\":null}" ;;
  *github/webhook*) echo '{"detail":"bad signature"}' ;;
  *Host:*) printf 302 ;;
  *) printf 200 ;;
esac
EOF
    chmod +x "$STUB_BIN/docker" "$STUB_BIN/curl"
}

teardown() {
    rm -rf "$TEST_DIR"
}

remote_pin() {
    git -C "$TEST_DIR/remote.git" show main:quack/docker-compose.yml | head -1
}

@test "with no sha it deploys the newest green build by digest, stopping quack-v1 before starting it" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$(remote_pin)" = "x-quack-v1-image: &quack-v1-image ghcr.io/fagerbergj/quack:v1-$NEW@sha256:abc" ]
    [ "$(git -C "$TEST_DIR/remote.git" log -1 --format=%s main)" = "quack v1: deploy 22222222" ]
    grep -q 'quack_quack-v1-data:/data:ro' "$TEST_DIR/docker.calls"
    [ "$(grep '^compose' "$TEST_DIR/docker.calls")" = "$(printf 'compose stop quack-v1\ncompose up -d quack-docker-gate quack-v1-init quack-v1')" ]
    [ ! -e "$TEST_DIR/mail.txt" ]
}

@test "a validate failure changes nothing and emails the reason" {
    VALIDATE_OUT="12 loaded, 1 failed" run bash "$SCRIPT" "$NEW"
    [ "$status" -eq 1 ]
    [ "$(remote_pin)" = "x-quack-v1-image: &quack-v1-image ghcr.io/fagerbergj/quack:v1-$OLD" ]
    git -C "$TEST_DIR/hs" diff --quiet HEAD
    ! grep -q '^compose' "$TEST_DIR/docker.calls"
    grep -q 'Subject: quack deploy failed: 22222222' "$TEST_DIR/mail.txt"
    grep -q 'did not report 0 failed' "$TEST_DIR/mail.txt"
}

@test "an unhealthy image is reverted, the revert is pushed, the old pin comes back up, and the owner is emailed" {
    BAD_SHA="$NEW" run bash "$SCRIPT" "$NEW"
    [ "$status" -eq 1 ]
    [ "$(remote_pin)" = "x-quack-v1-image: &quack-v1-image ghcr.io/fagerbergj/quack:v1-$OLD" ]
    [[ "$(git -C "$TEST_DIR/remote.git" log -2 --format=%s main)" == "quack v1: roll back to 11111111 (/version does not answer $NEW)"$'\n'"quack v1: deploy 22222222" ]]
    [ "$(grep -c '^compose up' "$TEST_DIR/docker.calls")" -eq 2 ]
    grep -q 'rolled back to 11111111' "$TEST_DIR/mail.txt"
}

@test "a sha without a green main build is refused before any image is touched" {
    run bash "$SCRIPT" 3333333333333333333333333333333333333333
    [ "$status" -eq 1 ]
    [ ! -e "$TEST_DIR/docker.calls" ]
    grep -q 'has no green main push run' "$TEST_DIR/mail.txt"
}

@test "deploying the sha already pinned does nothing" {
    GREEN="$OLD" run bash "$SCRIPT" "$OLD"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already on $OLD"* ]]
    [ ! -e "$TEST_DIR/docker.calls" ]
    [ ! -e "$TEST_DIR/mail.txt" ]
}
