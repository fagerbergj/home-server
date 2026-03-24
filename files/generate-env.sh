#!/bin/bash

set -e

cd "$(dirname "$0")"

ENV_FILE="../.env"

# Sets a key only if it doesn't already exist in .env
set_env() {
    local key=$1
    local value=$2
    if grep -q "^export ${key}=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s|^export ${key}=.*|export ${key}=${value}|" "$ENV_FILE"
    else
        echo "export ${key}=${value}" >> "$ENV_FILE"
    fi
}

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

set_secret NEXTCLOUD_DB_PASSWORD "$(openssl rand -hex 32)"
