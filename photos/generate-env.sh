#!/bin/bash

set -e

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

DB_USERNAME=immich
DB_DATABASE_NAME=immich

set_secret DB_PASSWORD "$(openssl rand -hex 32)"

# Read the current password (either just generated or pre-existing)
DB_PASSWORD=$(grep "^DB_PASSWORD=" .env | cut -d= -f2)

set_env DB_USERNAME "$DB_USERNAME"
set_env DB_DATABASE_NAME "$DB_DATABASE_NAME"
set_env DB_URL "postgresql://${DB_USERNAME}:${DB_PASSWORD}@immich-postgres/${DB_DATABASE_NAME}"
set_env REDIS_HOSTNAME "immich-redis"
