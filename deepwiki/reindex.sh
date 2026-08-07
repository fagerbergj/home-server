#!/usr/bin/env bash
# Reindex all tracked repos in deepwiki.
#
# To install as a nightly cron job (03:00), add these lines to root crontab:
#   $ echo '0 3 * * * /home/jason-server/workspace/home-server/deepwiki/reindex.sh >> "$LOG" 2>&1' | crontab -
set -euo pipefail

LOG="${DEEPWIKI_REINDEX_LOG:-$HOME/deepwiki-reindex.log}"

REPOS=(
  "https://github.com/fagerbergj/nightsout"
  "https://github.com/fagerbergj/home-server"
  "https://github.com/fagerbergj/quack"
  "https://github.com/fagerbergj/dotagents"
  "https://github.com/fagerbergj/document-pipeline"
  "https://github.com/fagerbergj/games"
)

for repo_url in "${REPOS[@]}"; do
  repo_name=$(basename "$repo_url")

  echo "[$(date '+%F %T')] Starting index for $repo_name ..."
  docker exec deepwiki curl -sfX POST "http://localhost:8001/wiki/tasks" \
    -H "Content-Type: application/json" \
    -d "{\"repo_url\": \"$repo_url\", \"type\": \"github\"}" || {
      echo "[$(date '+%F %T')] FAILED to submit task for $repo_name" >> "$LOG" 2>&1
      continue
  }

  while true; do
    resp=$(docker exec deepwiki curl -sf "http://localhost:8001/repo/index/status?repo_url=$repo_url&type=github" 2>/dev/null) || { echo "[$(date '+%F %T')] FAILED to get status for $repo_name, retrying..." >> "$LOG" 2>&1; sleep 30; continue; }
    status=$(echo "$resp" | python3 -c "import sys,json; print(str(json.load(sys.stdin).get('ready',False)).lower())")
    if [ "$status" = "true" ]; then break; fi
    sleep 30
  done

  echo "[$(date '+%F %T')] DONE $repo_name at $(date)" >> "$LOG" 2>&1
done

echo "[$(date '+%F %T')] Reindex complete at $(date)" >> "$LOG" 2>&1
