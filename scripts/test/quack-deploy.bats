#!/usr/bin/env bats
# Tests for quack/deploy.sh against a throwaway home-server clone and a bare remote.
# docker and curl are stubs: the fake stack serves whatever sha the pin names, unless that sha is BAD_SHA.

setup() {
    TEST_DIR="$(mktemp -d)"
    export TEST_DIR
    source "$BATS_TEST_DIRNAME/test_helper.bash"
    stub_bin_init
    SCRIPT="$BATS_TEST_DIRNAME/../../quack/deploy.sh"
    OLD=1111111111111111111111111111111111111111
    NEW=2222222222222222222222222222222222222222
    IMAGE="ghcr.io/fagerbergj/quack:v1-$NEW@sha256:abc"

    git init -q --bare -b main "$TEST_DIR/remote.git"
    git init -q -b main "$TEST_DIR/hs"
    mkdir -p "$TEST_DIR/hs/quack"
    printf 'x-quack-v1-image: &quack-v1-image ghcr.io/fagerbergj/quack:v1-%s\nservices: {}\n' "$OLD" > "$TEST_DIR/hs/quack/docker-compose.yml"
    git -C "$TEST_DIR/hs" add -A
    git -C "$TEST_DIR/hs" -c user.name=t -c user.email=t@t commit -q -m init
    git -C "$TEST_DIR/hs" push -q "$TEST_DIR/remote.git" HEAD:main

    export HOME_SERVER_DIR="$TEST_DIR/hs" HOME_SERVER_REMOTE="$TEST_DIR/remote.git" GH_TOKEN=test
    export QUACK_HEALTH_SECONDS=0 QUACK_SETTLE_SECONDS=0

    cat > "$STUB_BIN/docker" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$TEST_DIR/docker.calls"
case "$1 $2" in
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

@test "a healthy deploy pushes the digest pin and stops quack-v1 before starting it" {
    run bash "$SCRIPT" deploy "$NEW" "$IMAGE"
    [ "$status" -eq 0 ]
    [ "$(remote_pin)" = "x-quack-v1-image: &quack-v1-image $IMAGE" ]
    [ "$(git -C "$TEST_DIR/remote.git" log -1 --format=%s main)" = "quack v1: deploy 22222222" ]
    grep -q 'quack_quack-v1-data:/data:ro' "$TEST_DIR/docker.calls"
    [ "$(grep '^compose' "$TEST_DIR/docker.calls")" = "$(printf 'compose stop quack-v1\ncompose up -d quack-docker-gate quack-v1-init quack-v1')" ]
}

@test "a validate failure changes nothing: no commit, no push, no restart" {
    VALIDATE_OUT="12 loaded, 1 failed" run bash "$SCRIPT" deploy "$NEW" "$IMAGE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"did not report 0 failed"* ]]
    [ "$(remote_pin)" = "x-quack-v1-image: &quack-v1-image ghcr.io/fagerbergj/quack:v1-$OLD" ]
    git -C "$TEST_DIR/hs" diff --quiet HEAD
    ! grep -q '^compose' "$TEST_DIR/docker.calls"
}

@test "an unhealthy image is reverted, the revert is pushed, and the old pin comes back up" {
    BAD_SHA="$NEW" run bash "$SCRIPT" deploy "$NEW" "$IMAGE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"rolled back to 11111111"* ]]
    [ "$(remote_pin)" = "x-quack-v1-image: &quack-v1-image ghcr.io/fagerbergj/quack:v1-$OLD" ]
    [[ "$(git -C "$TEST_DIR/remote.git" log -2 --format=%s main)" == "quack v1: roll back to 11111111 (/version does not answer $NEW)"$'\n'"quack v1: deploy 22222222" ]]
    [ "$(grep -c '^compose up' "$TEST_DIR/docker.calls")" -eq 2 ]
}

@test "an image not pinned by digest is refused before anything runs" {
    run bash "$SCRIPT" deploy "$NEW" "ghcr.io/fagerbergj/quack:v1-$NEW"
    [ "$status" -eq 1 ]
    [ ! -e "$TEST_DIR/docker.calls" ]
}
