#!/bin/bash
# Checks whether anyone is actively using Plex, Minecraft, or Audiobookshelf.
# Safe to run before taking the server down.
#
# Usage:
#   PLEX_TOKEN=$TOKEN ABS_API_KEY=$KEY ./check-active-users.sh
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
    if echo "$result" | grep -qv "^0 "; then
        any_active=true
        # Extract player names after the colon
        players=$(echo "$result" | grep -oP '(?<=: ).+' || true)
        for player in ${players//,/ }; do
            printf "  %-20s online\n" "$player"
        done
    else
        echo "  No players online"
    fi
else
    echo "  Container not running"
fi

# --- Plex ---
echo ""
echo "=== Plex ==="
if [[ -z "${PLEX_TOKEN:-}" ]]; then
    echo "  Skipped (PLEX_TOKEN not set)"
else
    sessions=$(curl -sf "${PLEX_URL}/status/sessions?X-Plex-Token=${PLEX_TOKEN}" 2>/dev/null || echo "")
    if [[ -z "$sessions" ]]; then
        echo "  Could not reach Plex"
    else
        echo "$sessions" | python3 -c "
import sys, xml.etree.ElementTree as ET
root = ET.fromstring(sys.stdin.read())
videos = root.findall('.//Video')
if not videos:
    print('  No active streams')
else:
    for v in videos:
        user_el   = v.find('User');   user   = user_el.get('title', 'unknown')   if user_el   is not None else 'unknown'
        player_el = v.find('Player'); player = player_el.get('title', 'unknown') if player_el is not None else 'unknown'
        state     = player_el.get('state', 'unknown') if player_el is not None else 'unknown'
        show    = v.get('grandparentTitle', '')
        title   = v.get('title', 'Unknown')
        label   = '' if state == 'playing' else f'[{state}] '
        content = f'{label}{show}: {title}' if show else f'{label}{title}'
        offset  = int(v.get('viewOffset', 0)) // 60000
        print(f'  {user:<28} {(content[:45] + '...') if len(content) > 48 else content:<48} {player:<20} {offset}m in')
" 2>/dev/null
        count=$(echo "$sessions" | grep -oP '(?<=size=")[0-9]+' | head -1)
        count=${count:-0}
        if [[ "$count" -gt 0 ]]; then
            any_active=true
        fi
    fi
fi

# --- Audiobookshelf ---
echo ""
echo "=== Audiobookshelf ==="
if [[ -z "${ABS_API_KEY:-}" ]]; then
    echo "  Skipped (ABS_API_KEY not set)"
else
    abs_sessions=$(curl -sf "${ABS_URL}/api/sessions/open" \
        -H "Authorization: Bearer ${ABS_API_KEY}" 2>/dev/null || echo "")
    if [[ -z "$abs_sessions" ]]; then
        echo "  Could not reach Audiobookshelf"
    else
        abs_count=$(echo "$abs_sessions" | python3 -c "
import sys, json
data = json.load(sys.stdin)
sessions = data if isinstance(data, list) else data.get('sessions', [])
print(len(sessions))
" 2>/dev/null || echo 0)
        if [[ "$abs_count" -gt 0 ]]; then
            any_active=true
            echo "$abs_sessions" | python3 -c "
import sys, json, time
now_ms = time.time() * 1000
data = json.load(sys.stdin)
sessions = data if isinstance(data, list) else data.get('sessions', [])
for s in sessions:
    user    = s.get('user', {}).get('username', 'unknown')
    title   = s.get('displayTitle', 'Unknown')
    device  = s.get('deviceInfo', {}).get('deviceName', 'unknown device')
    age_sec = (now_ms - s.get('updatedAt', 0)) / 1000
    if age_sec < 120:
        label, age = '', 'now'
    elif age_sec < 3600:
        label, age = 'paused', f'{int(age_sec // 60)}m ago'
    else:
        label, age = 'idle', f'{int(age_sec // 3600)}h {int((age_sec % 3600) // 60)}m ago'
    content = f'[{label}] {title}' if label else title
    print(f'  {user:<28} {(content[:45] + '...') if len(content) > 48 else content:<48} {device:<20} {age}')
" 2>/dev/null
        else
            echo "  No active streams"
        fi
    fi
fi

# --- Summary ---
echo ""
if $any_active; then
    exit 1
else
    echo "All clear — safe to take the server down"
    exit 0
fi
