#!/bin/bash
# Interactive walkthrough to bring quack up on the server. Run it FROM the server,
# in this directory:  cd ~/workspace/home-server/quack && ./setup.sh
# Safe to re-run — it never destroys data; mutating steps ask first.
set -euo pipefail
cd "$(dirname "$0")"
ENV_FILE="../.env"

say()  { printf '\n\033[1;36m▶ %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*"; }
ask()  { local a; read -r -p "  $1 [y/N] " a; [[ "$a" == [yY]* ]]; }

# ── 1. Preflight ────────────────────────────────────────────────────────────
say "Preflight checks"
command -v docker >/dev/null || { echo "docker not found"; exit 1; }; ok "docker present"
for net in api_gateway llm_default; do
  if docker network inspect "$net" >/dev/null 2>&1; then ok "network '$net' exists";
  else echo "  MISSING network '$net' — bring up its owning compose first (api/ for api_gateway, llm/ for llm_default)"; exit 1; fi
done

# ── 2. Secrets in ../.env ───────────────────────────────────────────────────
say "Secrets ($ENV_FILE)"
touch "$ENV_FILE"; source "$ENV_FILE" 2>/dev/null || true
need_manual=0
for v in QUACK_GITHUB_APP_CLIENT_ID QUACK_GITHUB_APP_PRIVATE_KEY_PATH QUACK_EXA_API_KEY; do
  if [[ -n "${!v:-}" ]]; then ok "$v set"; else warn "$v is NOT set in $ENV_FILE — fill it, then re-run"; need_manual=1; fi
done
[[ "${QUACK_GITHUB_APP_PRIVATE_KEY_PATH:-}" && -f "${QUACK_GITHUB_APP_PRIVATE_KEY_PATH:-/nonexistent}" ]] \
  && ok "App private key found at $QUACK_GITHUB_APP_PRIVATE_KEY_PATH" \
  || { warn "App private key file not found — copy the .pem to the server and set QUACK_GITHUB_APP_PRIVATE_KEY_PATH"; need_manual=1; }
[[ "$need_manual" == 0 ]] || { echo; echo "Fill the missing values above in $ENV_FILE, then re-run ./setup.sh"; exit 1; }

say "Generating internal secrets (DB password + webhook secret)"
./generate-env.sh
source "$ENV_FILE" 2>/dev/null || true

# ── 3. Pull + start ─────────────────────────────────────────────────────────
say "Deploy"
warn "quack pulls ghcr.io/fagerbergj/quack:latest — that image must exist (cut a release: git tag v0.1.0 && git push origin v0.1.0) and be a PUBLIC package."
if ask "Pull the image and (re)start quack now?"; then
  docker compose pull
  docker compose up -d
else
  echo "Skipped. Run 'docker compose pull && docker compose up -d' when ready."; exit 0
fi

# ── 4. Verify the container ─────────────────────────────────────────────────
say "Verifying"
sleep 5
if docker logs quack 2>&1 | grep -q "github extension enabled"; then ok "GitHub App extension loaded";
else warn "did not see 'github extension enabled' yet — check: docker logs quack"; fi
if docker exec quack sh -c 'command -v curl >/dev/null' 2>/dev/null; then
  code=$(docker exec quack sh -c "curl -s -o /dev/null -w '%{http_code}' -XPOST http://localhost:8080/api/v1/github/webhook -d '{}'" 2>/dev/null || echo "?")
  [[ "$code" == "401" ]] && ok "webhook route live (bad-signature → 401)" || warn "webhook check returned '$code' (want 401)"
fi

# ── 5. Manual steps (only you can do these) ─────────────────────────────────
say "Manual steps to finish (outside this script)"
cat <<EOF
  1. NPM (admin UI :81): add Proxy Host
       quack.jasonfagerberg.duckdns.org  →  Traefik 'api' entrypoint (:8090)
       (TLS via the DuckDNS wildcard cert — same as api. / documents.)

  2. GitHub App  (github.com/settings/apps/quack-jason):
       Webhook URL    = https://quack.jasonfagerberg.duckdns.org/api/v1/github/webhook
       Webhook secret = ${QUACK_GITHUB_APP_WEBHOOK_SECRET:-<in $ENV_FILE>}
       Install the App on the repos to review (fagerbergj/quack, fagerbergj/games).

  3. Test:  post '@quack review this PR' on an installed repo.
     The App's 'Recent Deliveries' should show 202, then quack posts a review.
EOF
say "Done. Watchtower will auto-update quack when a new release moves :latest."
