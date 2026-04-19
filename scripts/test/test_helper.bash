#!/usr/bin/env bash
# Shared helpers for phase4-*.bats.
#
# Pattern: each test sets up TEST_DIR, calls `make_stub <name>` to install
# PATH shims that record their invocations into "$TEST_DIR/<name>.calls",
# then runs the script under test with PATH=$STUB_BIN:$PATH.

# Must be dot-sourced from a bats `setup` function. Expects TEST_DIR to be set.

stub_bin_init() {
    STUB_BIN="$TEST_DIR/bin"
    mkdir -p "$STUB_BIN"
    export STUB_BIN
    export PATH="$STUB_BIN:$PATH"
}

# make_stub <name> [body]
# Creates $STUB_BIN/<name>. Default body records args to <name>.calls and
# exits 0. A custom body can be provided for per-test overrides; the body
# receives $TEST_DIR in its environment.
make_stub() {
    local name="$1"
    local body="${2:-}"
    if [[ -z "$body" ]]; then
        body="echo \"\$*\" >> \"\$TEST_DIR/${name}.calls\""
    fi
    cat > "$STUB_BIN/$name" <<EOF
#!/usr/bin/env bash
$body
EOF
    chmod +x "$STUB_BIN/$name"
}

# Most phase4 scripts run things via sudo — the shim just execs the wrapped
# command, which will hit our other stubs via PATH.
make_sudo_stub() {
    cat > "$STUB_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
# sudo shim: drop the -rp/-S/etc. prefix flags, then exec the command.
while [[ $# -gt 0 ]]; do
    case "$1" in
        -*) shift ;;
        *) break ;;
    esac
done
exec "$@"
EOF
    chmod +x "$STUB_BIN/sudo"
}

# setfacl, apt, chown, chmod, mkdir — harmless record-only stubs
install_fs_stubs() {
    make_stub setfacl
    make_stub apt
    # chown/chmod/mkdir need to still function on the test filesystem so we
    # wrap the real ones and log. /bin/<cmd> bypasses PATH.
    cat > "$STUB_BIN/chown" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$TEST_DIR/chown.calls"
/bin/chown "$@" 2>/dev/null || true
EOF
    cat > "$STUB_BIN/chmod" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$TEST_DIR/chmod.calls"
/bin/chmod "$@" 2>/dev/null || true
EOF
    cat > "$STUB_BIN/mkdir" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$TEST_DIR/mkdir.calls"
/bin/mkdir "$@"
EOF
    chmod +x "$STUB_BIN/chown" "$STUB_BIN/chmod" "$STUB_BIN/mkdir"
}

# getent stub driven by a fixture file: TEST_DIR/getent.db
# File format, one per line:   passwd|<name>|<uid>
#                              group|<name>|<gid>
make_getent_stub() {
    cat > "$STUB_BIN/getent" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$TEST_DIR/getent.calls"
db="$1"; name="$2"
while IFS='|' read -r d n v; do
    if [[ "$d" == "$db" && "$n" == "$name" ]]; then
        case "$db" in
            passwd) echo "$n:x:$v:$v::/home/$n:/bin/bash" ;;
            group)  echo "$n:x:$v:" ;;
        esac
        exit 0
    fi
done < "$TEST_DIR/getent.db"
exit 2
EOF
    chmod +x "$STUB_BIN/getent"
}

# id stub — reads the same fixture file.
make_id_stub() {
    cat > "$STUB_BIN/id" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$TEST_DIR/id.calls"
# Support `id -u <user>` only — phase4 scripts never use other forms.
if [[ "$1" == "-u" ]]; then
    name="$2"
    while IFS='|' read -r d n v; do
        [[ "$d" == "passwd" && "$n" == "$name" ]] && { echo "$v"; exit 0; }
    done < "$TEST_DIR/getent.db"
    exit 1
fi
echo "id: unexpected args: $*" >&2
exit 1
EOF
    chmod +x "$STUB_BIN/id"
}

# Populate TEST_DIR/getent.db with the post-migration set of users/groups.
seed_default_users_and_groups() {
    cat > "$TEST_DIR/getent.db" <<'EOF'
passwd|plex|999
passwd|immich|996
passwd|qbittorrent|994
passwd|sonarr|988
passwd|radarr|987
passwd|audiobookshelf|995
passwd|minecraft|993
group|plex-rw|1001
group|plex-ro|1002
group|personal-rw|1003
group|personal-ro|1004
EOF
}
