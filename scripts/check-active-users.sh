#!/bin/bash
# Checks whether anyone is actively using Plex, Minecraft, or Audiobookshelf.
# Safe to run before taking the server down.
#
# Usage:
#   PLEX_TOKEN=$TOKEN ./check-active-users.sh
#
# Environment:
#   PLEX_TOKEN   Plex auth token (required for Plex check)
#   PLEX_URL     Plex base URL (default: http://localhost:32400)
#   ABS_URL      Audiobookshelf base URL (default: http://localhost:13378)

set -euo pipefail

PLEX_URL="${PLEX_URL:-http://localhost:32400}"
ABS_URL="${ABS_URL:-http://localhost:13378}"

any_active=false

# --- Minecraft ---
echo "=== Minecraft ==="
if docker ps --format '{{.Names}}' | grep -q '^minecraft$'; then
    result=$(docker exec minecraft rcon-cli list 2>/dev/null || echo "rcon unavailable")
    echo "$result"
    if echo "$result" | grep -qv "^0 "; then
        any_active=true
    fi
else
    echo "Container not running"
fi

# --- Plex ---
echo ""
echo "=== Plex ==="
if [[ -z "${PLEX_TOKEN:-}" ]]; then
    echo "Skipped (PLEX_TOKEN not set)"
else
    sessions=$(curl -sf "${PLEX_URL}/status/sessions?X-Plex-Token=${PLEX_TOKEN}" 2>/dev/null || echo "")
    if [[ -z "$sessions" ]]; then
        echo "Could not reach Plex"
    else
        count=$(echo "$sessions" | grep -o 'size="[0-9]*"' | grep -o '[0-9]*' | head -1 || echo 0)
        if [[ "$count" -gt 0 ]]; then
            echo "${count} active stream(s)"
            # Print user + title for each session
            echo "$sessions" | grep -oP '(?<=title=")[^"]+' | head -20
            any_active=true
        else
            echo "No active streams"
        fi
    fi
fi

# --- Audiobookshelf ---
echo ""
echo "=== Audiobookshelf ==="
connections=$(ss -tn 2>/dev/null | grep -c 'ESTAB.*13378\|13378.*ESTAB' || echo 0)
if [[ "$connections" -gt 0 ]]; then
    echo "${connections} active connection(s)"
    any_active=true
else
    echo "No active connections"
fi

# --- Summary ---
echo ""
if $any_active; then
    echo "ACTIVE USERS DETECTED — do not take the server down yet"
    exit 1
else
    echo "All clear — safe to take the server down"
    exit 0
fi
