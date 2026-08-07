#!/bin/bash

set -e

cd "$(dirname "$0")"

ENV_FILE="./.env"
OLD_ENV_FILE="../.env"

# Sets a key to a fixed value, overwriting whatever is there — safe to re-run
set_env() {
    local key=$1
    local value=$2
    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
    else
        echo "${key}=${value}" >> "$ENV_FILE"
    fi
}

touch "$ENV_FILE"
chmod 600 "$ENV_FILE"

DB_USERNAME=immich
DB_DATABASE_NAME=immich

set_env DB_USERNAME "$DB_USERNAME"
set_env DB_DATABASE_NAME "$DB_DATABASE_NAME"
set_env REDIS_HOSTNAME "immich-redis"

# DB_PASSWORD is already baked into the immich-postgres role/volume. Generating a
# fresh one here would silently rotate a value the container never rotates, so
# this only carries the existing value forward (migration case) or leaves it
# for the operator — it never invents one, idempotent like quack's set_secret.
if grep -q "^DB_PASSWORD=.\+" "$ENV_FILE" 2>/dev/null; then
    echo "DB_PASSWORD already set — skipping"
elif [ -f "$OLD_ENV_FILE" ] && grep -q "^\(export \)\?DB_PASSWORD=.\+" "$OLD_ENV_FILE"; then
    old_value=$(grep "^\(export \)\?DB_PASSWORD=" "$OLD_ENV_FILE" | tail -1 | cut -d= -f2-)
    set_env DB_PASSWORD "$old_value"
    echo "DB_PASSWORD carried forward unchanged from $OLD_ENV_FILE"
else
    set_env DB_PASSWORD ""
    echo "DB_PASSWORD is empty — set it by hand to the value already in immich-postgres"
fi

DB_PASSWORD=$(grep "^DB_PASSWORD=" "$ENV_FILE" | cut -d= -f2-)
set_env DB_URL "postgresql://${DB_USERNAME}:${DB_PASSWORD}@immich-postgres/${DB_DATABASE_NAME}"

chmod 600 "$ENV_FILE"

echo
echo "DB_PASSWORD was NOT rotated. If you ever change it by hand, also run:"
echo "  docker exec immich-postgres psql -U immich -c \"ALTER USER immich WITH PASSWORD '<new value>'\""
echo "so the Postgres role matches — a mismatch locks immich-server out of its own database."
