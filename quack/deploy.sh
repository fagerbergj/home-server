#!/usr/bin/env bash
# Deploys a quack-v1 image on jason-server. Run it on the server, e.g. over the tailnet:
#   ssh jason-server@jason-server.hs.internal '~/workspace/home-server/quack/deploy.sh [sha]'
#
#   deploy.sh            deploy the newest green quack main build
#   deploy.sh <sha>      deploy that full 40-character quack commit (it must have a green main build)
#   deploy.sh --mail-test  send one test email through the failure-mail path
#
# Steps: resolve v1-<sha> to its digest, run validate.ts read-only against prod (must print 0 failed), commit and push
# the pin, stop quack-v1, then up the gate, init and quack-v1, health-check, and on failure revert, push and restart the
# old pin. Any failure emails the owner through the SMTP settings Watchtower uses (updater/).
set -Eeuo pipefail

HS="${HOME_SERVER_DIR:-$HOME/workspace/home-server}"
QUACK_RUNS="${QUACK_RUNS_API:-https://api.github.com/repos/fagerbergj/quack/actions/workflows/v1.yaml/runs}"
TAILNET_URL="${QUACK_TAILNET_URL:-http://100.64.0.6:18081}"
TRAEFIK_URL="${QUACK_TRAEFIK_URL:-http://127.0.0.1:8090}"
PUBLIC_HOST="${QUACK_PUBLIC_HOST:-quack.jasonfagerberg.duckdns.org}"
HEALTH_SECONDS="${QUACK_HEALTH_SECONDS:-180}"
SETTLE_SECONDS="${QUACK_SETTLE_SECONDS:-30}"
LOCK="${QUACK_DEPLOY_LOCK:-/tmp/quack-deploy.lock}"
COMPOSE="$HS/quack/docker-compose.yml"
REPO=ghcr.io/fagerbergj/quack
PIN_KEY='x-quack-v1-image: &quack-v1-image'

log() { echo "deploy: $*" >&2; }
# die often runs inside $(...), so the message reaches the failure email through a file, not a variable.
die() { echo "$*" >>"${FAIL_FILE:-/dev/null}"; echo "deploy: error: $*" >&2; exit 1; }

current_pin() { sed -n "s|^$PIN_KEY ||p" "$COMPOSE"; }
set_pin() { sed -i "s|^$PIN_KEY .*|x-quack-v1-image: \\&quack-v1-image $1|" "$COMPOSE"; }
commit() { git -C "$HS" -c user.name='quack deploy' commit -q -m "$1" -m "deployed by quack/deploy.sh on $(hostname)" -- quack/docker-compose.yml; }
push() { GIT_TERMINAL_PROMPT=0 git -C "$HS" push -q origin HEAD:main; }

# quack is public, so the GitHub API needs no token here; a green main push run means check passed and v1-<sha> exists.
green_runs() { curl -fsS --max-time 20 "$QUACK_RUNS?branch=main&event=push&status=success&$1"; }
resolve_sha() {
  local sha=${1:-}
  [[ -n $sha ]] || sha=$(green_runs per_page=1 | jq -r '.workflow_runs[0].head_sha // empty')
  [[ $sha =~ ^[0-9a-f]{40}$ ]] || die "want a full 40-character quack commit sha, got '$sha'"
  [[ $(green_runs "head_sha=$sha" | jq -r '.total_count') -gt 0 ]] || die "$sha has no green main push run of quack's v1.yaml"
  echo "$sha"
}
resolve_image() {
  local digest
  digest=$(docker buildx imagetools inspect "$REPO:v1-$1" --format '{{.Manifest.Digest}}')
  [[ $digest == sha256:* ]] || die "no digest for $REPO:v1-$1"
  echo "$REPO:v1-$1@$digest"
}

# Today's read-only check of the new image against prod's data and config.
validate() {
  local out
  out=$(docker run --rm -l traefik.enable=false \
    -v quack_quack-v1-data:/data:ro -v "$HS/quack/v1-deployment.json:/config/deployment.json:ro" \
    -e QUACK_CONFIG=/config/deployment.json -e QUACK_AGENTS_DIR=/app/agents -e QUACK_DATA_DIR=/data \
    "$1" node packages/runtime/src/validate.ts 2>&1) || true
  echo "$out" >&2
  grep -qE '^[0-9]+ loaded, 0 failed$' <<<"$out"
}

# Stop first so quack-v1 drains while the old gate is still up; the gate and quack-v1 share the pin.
restart() {
  (cd "$HS/quack" && docker compose stop quack-v1 && docker compose up -d quack-docker-gate quack-v1-init quack-v1)
}

check() {
  local sha=$1 state code
  state=$(docker inspect -f '{{.State.Running}} {{.RestartCount}}' quack-v1 2>/dev/null) || state=missing
  [[ $state == "true 0" ]] || { why="quack-v1 is not running cleanly ($state)"; return 1; }
  curl -fsS --max-time 5 "$TAILNET_URL/version" 2>/dev/null | grep -q "\"commit\":\"$sha\"" || { why="/version does not answer $sha"; return 1; }
  code=$(curl -s --max-time 5 -o /dev/null -w '%{http_code}' "$TAILNET_URL/") || true
  [[ $code == 200 ]] || { why="the UI on the tailnet answered $code"; return 1; }
  code=$(curl -s --max-time 5 -o /dev/null -w '%{http_code}' -H "Host: $PUBLIC_HOST" "$TRAEFIK_URL/") || true
  [[ $code == 30? || $code == 401 ]] || { why="the UI through Traefik answered $code, not Authentik's sign-in"; return 1; }
  curl -s --max-time 5 -X POST -H "Host: $PUBLIC_HOST" "$TRAEFIK_URL/github/webhook" 2>/dev/null | grep -q 'bad signature' ||
    { why="an unsigned webhook did not answer bad signature"; return 1; }
}

# Healthy within HEALTH_SECONDS and still healthy SETTLE_SECONDS later, so a crash loop after boot counts.
healthy() {
  local deadline=$((SECONDS + HEALTH_SECONDS))
  until check "$1"; do
    ((SECONDS < deadline)) || { log "unhealthy: $why"; return 1; }
    sleep 5
  done
  sleep "$SETTLE_SECONDS"
  check "$1" || { log "unhealthy after settling: $why"; return 1; }
}

rollback() {
  local deployed=$1 old_sha=$2 reason=$3
  git -C "$HS" revert --no-commit "$deployed"
  commit "quack v1: roll back to ${old_sha:0:8} ($reason)"
  push || log "pushing the revert failed: home-server main still names the bad pin; push it by hand"
  restart
  healthy "$old_sha" || die "deploy failed ($reason) and the rollback to ${old_sha:0:8} is unhealthy too: $why"
  die "deploy failed ($reason); rolled back to ${old_sha:0:8}"
}

deploy() {
  local sha image old old_sha deployed
  [[ $(git -C "$HS" symbolic-ref --short HEAD) == main ]] || die "$HS is not on main"
  git -C "$HS" diff --quiet HEAD || die "$HS has uncommitted changes to tracked files; commit or discard them first"
  git -C "$HS" pull -q --ff-only origin main
  sha=$(resolve_sha "${1:-}")
  old=$(current_pin)
  [[ $old != *":v1-$sha"* ]] || { log "already on $sha"; return 0; }
  old_sha=$(sed -E 's/.*:v1-([0-9a-f]{40}).*/\1/' <<<"$old")
  [[ $old_sha =~ ^[0-9a-f]{40}$ ]] || die "cannot read the current pin from $COMPOSE, so a rollback would have no target"
  image=$(resolve_image "$sha")
  set_pin "$image"
  validate "$image" || { git -C "$HS" checkout -- quack/docker-compose.yml; die "validate.ts did not report 0 failed for $image; nothing changed"; }
  commit "quack v1: deploy ${sha:0:8}"
  deployed=$(git -C "$HS" rev-parse HEAD)
  push || { git -C "$HS" reset -q --hard HEAD~1; die "pushing the pin failed; nothing deployed"; }
  restart
  healthy "$sha" || rollback "$deployed" "$old_sha" "$why"
  log "deployed $sha"
}

mail() {
  local subject=$1 from to server port user pw
  watchtower() { sed -n "s/^ *- WATCHTOWER_NOTIFICATION_EMAIL_$1=//p" "$HS/updater/docker-compose.yml"; }
  from=$(watchtower FROM) to=$(watchtower TO) server=$(watchtower SERVER) port=$(watchtower SERVER_PORT) user=$(watchtower SERVER_USER)
  pw=$(sed -n 's/^GMAIL_APP_PASSWORD=//p' "$HS/updater/.env" 2>/dev/null) || true
  pw=${pw#\"} pw=${pw%\"}
  [[ -n $pw && -n $to ]] || { log "no GMAIL_APP_PASSWORD in updater/.env or no recipient in updater/docker-compose.yml; cannot mail"; return 1; }
  { printf 'From: %s\r\nTo: %s\r\nSubject: %s\r\n\r\n' "$from" "$to" "$subject"; cat; } |
    curl -sS --max-time 30 --url "smtp://$server:$port" --ssl-reqd --mail-from "$from" --mail-rcpt "$to" \
      -K <(printf 'user = "%s:%s"\n' "$user" "$pw") -T -
}

on_exit() {
  local rc=$? msg
  msg=$(cat "$FAIL_FILE" 2>/dev/null) || true
  rm -f "$FAIL_FILE"
  ((rc == 0)) && return 0
  printf 'quack deploy on %s exited %s.\n%s\n' "$(hostname)" "$rc" "${msg:-command '${fail_cmd:-?}' failed at line ${fail_line:-?}}" |
    mail "quack deploy failed${SHA_ARG:+: ${SHA_ARG:0:8}}" || log "the failure email did not go out"
  exit "$rc"
}

main() {
  if [[ ${1:-} == --mail-test ]]; then
    echo "test from quack/deploy.sh" | mail "quack deploy mail test"
    return
  fi
  SHA_ARG=${1:-}
  FAIL_FILE=$(mktemp)
  trap 'fail_cmd=$BASH_COMMAND fail_line=$LINENO' ERR
  trap on_exit EXIT
  exec 9>"$LOCK"
  flock -n 9 || die "another deploy holds $LOCK"
  deploy "$@"
}

# One line, so bash has read all of it before `git pull` can rewrite this file mid-run.
main "$@"; exit
