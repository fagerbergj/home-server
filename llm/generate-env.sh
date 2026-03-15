#!/bin/bash

set -e

cd "$(dirname "$0")"

ENV_FILE="../.env"

# Generates and sets a key only if not already present — safe to re-run
set_secret() {
    local key=$1
    local value=$2
    if ! grep -q "^${key}=.\+" "$ENV_FILE" 2>/dev/null; then
        echo "${key}=${value}" >> "$ENV_FILE"
        echo "${key} generated"
    else
        echo "${key} already set — skipping"
    fi
}

touch "$ENV_FILE"

set_secret OLLAMA_API_KEY "$(openssl rand -hex 32)"
