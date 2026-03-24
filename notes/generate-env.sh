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

set_secret RMFAKECLOUD_JWT_SECRET_KEY "$(openssl rand -hex 32)"
set_secret COUCHDB_USER "admin"
set_secret COUCHDB_PASSWORD "$(openssl rand -hex 24)"
