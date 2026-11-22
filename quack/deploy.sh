#!/usr/bin/env bash
# Cuts quack-v1 over to one image on this host; .github/workflows/quack-deploy.yaml runs it on jason-server's runner.
#   deploy.sh deploy <sha> <ghcr.io/fagerbergj/quack:v1-<sha>@sha256:...>
#   deploy.sh notify <subject> < body     mails through the SMTP settings Watchtower uses (updater/)
set -euo pipefail

HS="${HOME_SERVER_DIR:-$HOME/workspace/home-server}"
REMOTE="${HOME_SERVER_REMOTE:-https://github.com/fagerbergj/home-server.git}"
TAILNET_URL="${QUACK_TAILNET_URL:-http://100.64.0.6:18081}"
TRAEFIK_URL="${QUACK_TRAEFIK_URL:-http://127.0.0.1:8090}"
PUBLIC_HOST="${QUACK_PUBLIC_HOST:-quack.jasonfagerberg.duckdns.org}"
HEALTH_SECONDS="${QUACK_HEALTH_SECONDS:-180}"
SETTLE_SECONDS="${QUACK_SETTLE_SECONDS:-30}"
COMPOSE="$HS/quack/docker-compose.yml"
PIN_KEY='x-quack-v1-image: &quack-v1-image'
RUN_URL="${GITHUB_RUN_ID:+$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID}"

log() { echo "deploy: $*" >&2; }
die() { echo "::error::$*" >&2; exit 1; }

current_pin() { sed -n "s|^$PIN_KEY ||p" "$COMPOSE"; }
set_pin() { sed -i "s|^$PIN_KEY .*|x-quack-v1-image: \\&quack-v1-image $1|" "$COMPOSE"; }

commit() {
  git -C "$HS" -c user.name='github-actions[bot]' -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
    commit -q -m "$1" -m "${RUN_URL:-run by hand}" -- quack/docker-compose.yml
}

# The job token goes in through git's env config, so it never shows in a process listing.
push() {
  local auth
  auth=$(printf 'x-access-token:%s' "${GH_TOKEN:?GH_TOKEN is required to push}" | base64 -w0)
  GIT_TERMINAL_PROMPT=0 GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="http.https://github.com/.extraheader" \
    GIT_CONFIG_VALUE_0="AUTHORIZATION: basic $auth" git -C "$HS" push -q "$REMOTE" HEAD:main
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
  local sha=${1:-} image=${2:-} old old_sha deployed
  [[ $sha =~ ^[0-9a-f]{40}$ ]] || die "want a full 40-character commit sha, got '$sha'"
  [[ $image == "ghcr.io/fagerbergj/quack:v1-$sha@sha256:"* ]] || die "want ghcr.io/fagerbergj/quack:v1-$sha pinned by digest, got '$image'"
  [[ $(git -C "$HS" symbolic-ref --short HEAD) == main ]] || die "$HS is not on main"
  git -C "$HS" diff --quiet HEAD || die "$HS has uncommitted changes to tracked files; commit or discard them first"
  git -C "$HS" pull -q --ff-only "$REMOTE" main
  old=$(current_pin)
  [[ $old != *":v1-$sha"* ]] || { log "already on $sha"; return 0; }
  old_sha=$(sed -E 's/.*:v1-([0-9a-f]{40}).*/\1/' <<<"$old")
  [[ $old_sha =~ ^[0-9a-f]{40}$ ]] || die "cannot read the current pin from $COMPOSE, so a rollback would have no target"
  set_pin "$image"
  validate "$image" || { git -C "$HS" checkout -- quack/docker-compose.yml; die "validate.ts did not report 0 failed for $image; nothing changed"; }
  commit "quack v1: deploy ${sha:0:8}"
  deployed=$(git -C "$HS" rev-parse HEAD)
  push || { git -C "$HS" reset -q --hard HEAD~1; die "pushing the pin failed; nothing deployed"; }
  restart
  healthy "$sha" || rollback "$deployed" "$old_sha" "$why"
  log "deployed $sha"
}

notify() {
  local subject=${1:?subject} from to server port user pw
  watchtower() { sed -n "s/^ *- WATCHTOWER_NOTIFICATION_EMAIL_$1=//p" "$HS/updater/docker-compose.yml"; }
  from=$(watchtower FROM) to=$(watchtower TO) server=$(watchtower SERVER) port=$(watchtower SERVER_PORT) user=$(watchtower SERVER_USER)
  pw=$(sed -n 's/^GMAIL_APP_PASSWORD=//p' "$HS/updater/.env" 2>/dev/null) || true
  pw=${pw#\"} pw=${pw%\"}
  [[ -n $pw && -n $to ]] || die "no GMAIL_APP_PASSWORD in $HS/updater/.env or no recipient in updater/docker-compose.yml; cannot mail"
  { printf 'From: %s\r\nTo: %s\r\nSubject: %s\r\n\r\n' "$from" "$to" "$subject"; cat; } |
    curl -sS --max-time 30 --url "smtp://$server:$port" --ssl-reqd --mail-from "$from" --mail-rcpt "$to" \
      -K <(printf 'user = "%s:%s"\n' "$user" "$pw") -T -
}

case "${1:-}" in
  deploy) shift; deploy "$@" ;;
  notify) shift; notify "$@" ;;
  *) echo "usage: $0 deploy <sha> <image@digest> | notify <subject> < body" >&2; exit 2 ;;
esac
