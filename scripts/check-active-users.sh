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
#   ABS_API_KEY  Audiobookshelf API token (required for ABS check)
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
        count=$(echo "$sessions" | grep -oP '(?<=size=")[0-9]+' | head -1)
        count=${count:-0}
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
if [[ -z "${ABS_API_KEY:-}" ]]; then
    echo "Skipped (ABS_API_KEY not set)"
else
    abs_sessions=$(curl -sf "${ABS_URL}/api/sessions/open" \
        -H "Authorization: Bearer ${ABS_API_KEY}" 2>/dev/null || echo "")
    if [[ -z "$abs_sessions" ]]; then
        echo "Could not reach Audiobookshelf"
    else
        abs_count=$(echo "$abs_sessions" | python3 -c "
import sys, json
data = json.load(sys.stdin)
sessions = data if isinstance(data, list) else data.get('sessions', [])
print(len(sessions))
" 2>/dev/null || echo 0)
        if [[ "$abs_count" -gt 0 ]]; then
            echo "${abs_count} open session(s)"
            echo "$abs_sessions" | python3 -c "
import sys, json, time
now_ms = time.time() * 1000
data = json.load(sys.stdin)
sessions = data if isinstance(data, list) else data.get('sessions', [])
for s in sessions:
    title    = s.get('displayTitle', 'Unknown')
    updated  = s.get('updatedAt', 0)
    device   = s.get('deviceInfo', {}).get('deviceName', 'unknown device')
    age_sec  = (now_ms - updated) / 1000
    if age_sec < 120:
        status = 'playing'
    elif age_sec < 3600:
        status = f'paused {int(age_sec // 60)}m ago'
    else:
        status = f'idle {int(age_sec // 3600)}h {int((age_sec % 3600) // 60)}m ago'
    print(f'  {title} — {status} [{device}]')
" 2>/dev/null
            any_active=true
        else
            echo "No active streams"
        fi
    fi
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
