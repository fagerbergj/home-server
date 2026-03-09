#!/bin/bash

set -e

cd "$(dirname "$0")"

# Sets a key only if it doesn't already exist in .env
set_env() {
    local key=$1
    local value=$2
    if grep -q "^${key}=" .env 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
        echo "${key}=${value}" >> .env
    fi
}

# Generates and sets a key only if not already present — safe to re-run
set_secret() {
    local key=$1
    local value=$2
    if ! grep -q "^${key}=" .env 2>/dev/null; then
        echo "${key}=${value}" >> .env
        echo "${key} generated"
    else
        echo "${key} already set — skipping"
    fi
}

touch .env

set_secret OLLAMA_API_KEY "$(openssl rand -hex 32)"
