#!/bin/bash
set -e
cd "$(dirname "$0")"

ENV_FILE="./.env"

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
chmod 600 "$ENV_FILE"

# shared-postgres is a live database. If it already has a role password from
# the old root .env, paste that value into SHARED_DB_PASSWORD in this file
# BEFORE running this script, so set_secret skips it below. Otherwise this
# generates a new password the running postgres doesn't know, and every
# service on shared-postgres (currently document-pipeline) is locked out
# until you `ALTER USER "$SHARED_DB_USER" WITH PASSWORD '...'` to match.
set_secret SHARED_DB_USER "shared"
set_secret SHARED_DB_PASSWORD "$(openssl rand -hex 24)"

echo
echo "Still set by hand in $ENV_FILE (not auto-generated):"
echo "  OCR_MODEL, CLARIFY_MODEL, CLASSIFY_MODEL, EMBED_MODEL,"
echo "  CONTEXTUAL_MODEL, CHAT_MODEL, SUMMARIZE_MODEL — llm-swap.yaml model keys"
echo "  LLM_API_KEY               — leave empty, llm-swap doesn't authenticate"
echo "  WHISPER_URL, WHISPER_MODEL, QDRANT_COLLECTION, QDRANT_API_KEY,"
echo "  OPENSEARCH_INDEX          — optional, docker-compose.yml has defaults"
echo "  OPEN_WEBUI_URL            — internal URL, http://open-webui:8080"
echo "  OPEN_WEBUI_API_KEY        — Open WebUI → Settings → Account → API Keys"
echo "  OPEN_WEBUI_KNOWLEDGE_ID   — Open WebUI → Workspace → Knowledge"
