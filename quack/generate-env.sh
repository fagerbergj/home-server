#!/bin/bash

set -e

cd "$(dirname "$0")"

ENV_FILE="../.env"

# Generates and sets a key only if not already present — safe to re-run
set_secret() {
    local key=$1
    local value=$2
    if grep -q "^export ${key}=.\+" "$ENV_FILE" 2>/dev/null; then
        echo "${key} already set — skipping"
    elif grep -q "^export ${key}=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s|^export ${key}=.*|export ${key}=${value}|" "$ENV_FILE"
        echo "${key} generated"
    else
        echo "export ${key}=${value}" >> "$ENV_FILE"
        echo "${key} generated"
    fi
}

touch "$ENV_FILE"

# Internal Postgres password — quack only.
set_secret QUACK_DB_PASSWORD "$(openssl rand -hex 24)"

# GitHub webhook secret. Generated here if unset — then paste the SAME value into
# the GitHub App's Webhook secret field (github.com/settings/apps/quack-jason) so
# the HMAC signatures match.
set_secret QUACK_GITHUB_APP_WEBHOOK_SECRET "$(openssl rand -hex 32)"

echo
echo "Still set by hand in ../.env (not auto-generated):"
echo "  QUACK_GITHUB_APP_CLIENT_ID        — from the GitHub App (Iv23li...)"
echo "  QUACK_GITHUB_APP_PRIVATE_KEY_PATH — absolute path to the App .pem on this host"
echo "  QUACK_EXA_API_KEY                 — Exa search key"
