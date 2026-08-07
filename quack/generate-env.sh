#!/bin/bash

set -e

cd "$(dirname "$0")"

ENV_FILE="./.env"

# Generates and sets a key only if not already present — safe to re-run
set_secret() {
    local key=$1
    local value=$2
    if grep -q "^${key}=.\+" "$ENV_FILE" 2>/dev/null; then
        echo "${key} already set — skipping"
    elif grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
        echo "${key} generated"
    else
        echo "${key}=${value}" >> "$ENV_FILE"
        echo "${key} generated"
    fi
}

umask 077
touch "$ENV_FILE"
chmod 600 "$ENV_FILE"

# Internal Postgres password. Only generated when unset: quack-postgres already
# holds the old one, so changing it here also needs
#   docker exec quack-postgres psql -U quack -c "ALTER USER quack WITH PASSWORD '<new>'"
set_secret QUACK_DB_PASSWORD "$(openssl rand -hex 24)"

# GitHub webhook secret. Generated here if unset — then paste the SAME value into
# the GitHub App's Webhook secret field (github.com/settings/apps/quack-jason) so
# the HMAC signatures match.
set_secret QUACK_GITHUB_APP_WEBHOOK_SECRET "$(openssl rand -hex 32)"

echo
echo "Still set by hand in quack/.env (not auto-generated):"
echo "  QUACK_GITHUB_APP_CLIENT_ID        — from the GitHub App (Iv23li...)"
echo "  QUACK_GITHUB_APP_PRIVATE_KEY_PATH — absolute path to the App .pem on this host"
echo "  QUACK_EXA_API_KEY                 — Exa search key"
