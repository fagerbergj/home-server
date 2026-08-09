#!/usr/bin/env bash
# Incrementally reindex tracked repos in deepwiki.
#
# deepwiki-open has no incremental update at any layer: the wiki-page cache
# short-circuits a resubmit to a no-op (api/services/wiki/tasks.py
# wiki_cache_exists gate, checked BEFORE indexing even starts), the
# embedding cache is all-or-nothing (api/rag/pipeline.py), and the clone is
# never re-pulled (api/repository.py, no `git fetch`/`pull`). This script is
# the incremental layer deepwiki doesn't have: it only touches a repo whose
# upstream default branch actually moved since the last VERIFIED success, by
# deleting that repo's clone + embedding db + wiki-page cache and letting
# deepwiki rebuild it from scratch - a full re-embed, but only for repos
# that changed.
#
# CRON IS CURRENTLY DISABLED on jason-server (commented out in root's/the
# deploy user's crontab) - the re-index-on-change path above has not yet
# been exercised end to end on this host (queue contention during rollout
# prevented a full observed run; see the commit that introduced this
# comment for exactly what was and wasn't verified). Re-enabling is a
# deliberate step to take once that path has actually been watched
# through to a completed, verified run - don't just uncomment this on
# faith.
#
# To re-enable as a nightly cron job (03:00):
#   $ crontab -l | { cat; echo '0 3 * * * /home/jason-server/workspace/home-server/deepwiki/reindex.sh >> $HOME/deepwiki-reindex.log 2>&1'; } | crontab -
#
# Cadence should stay nightly once re-enabled: the skip path is cheap (one
# `git ls-remote` per repo), but a real reindex is still a CPU-heavy embed
# job on the same box that serves quack's models, so it should stay confined
# to off-peak hours rather than firing more often.

STATE="${DEEPWIKI_REINDEX_STATE:-$HOME/.deepwiki-reindex.state}"
API="http://localhost:3007/api"
# openrouter is the only client that reaches llm-swap: the others go through
# adalflow's OpenAIClient, which speaks OpenAI's Responses API exclusively.
PROVIDER="${DEEPWIKI_PROVIDER:-openrouter}"
MODEL="${DEEPWIKI_MODEL:-qwen3.6-35b}"
CONTAINER="deepwiki"
POLL_INTERVAL=30
# 12h. A CPU embedder puts a large repo hours past any tidy ceiling, and giving
# up early does not stop the task - it finishes unrecorded and gets redone.
POLL_MAX=1440

set -u

REPOS=(
  "https://github.com/fagerbergj/nightsout"
  "https://github.com/fagerbergj/home-server"
  "https://github.com/fagerbergj/quack"
  "https://github.com/fagerbergj/dotagents"
  "https://github.com/fagerbergj/document-pipeline"
  "https://github.com/fagerbergj/games"
)

log() { echo "[$(date '+%F %T')] $*"; }

touch "$STATE"

state_get() {
  awk -F'\t' -v k="$1" '$1==k{print $2; found=1} END{if(!found) exit 1}' "$STATE"
}

state_set() {
  local key="$1" sha="$2" tmp
  tmp=$(mktemp "${STATE}.XXXXXX")
  awk -F'\t' -v k="$key" '$1!=k' "$STATE" >"$tmp"
  printf '%s\t%s\n' "$key" "$sha" >>"$tmp"
  mv "$tmp" "$STATE"
}

# One repo at a time, own scope for its intermediate vars - a failure here
# must never take the rest of the loop down with it (no top-level set -e).
reindex_one() {
  local repo_url="$1" repo_name repo_owner key remote_sha last_sha
  local active_resp active_id submit task_id status since resp err
  local non_empty_max cache_check

  repo_name=$(basename "$repo_url")
  repo_owner=$(basename "$(dirname "$repo_url")")
  key="${repo_owner}/${repo_name}"

  remote_sha=$(git ls-remote "$repo_url" HEAD 2>/dev/null | cut -f1)
  if [ -z "$remote_sha" ]; then
    log "FAIL $key: could not resolve remote HEAD via git ls-remote"
    return 1
  fi

  last_sha=$(state_get "$key" || true)

  if [ "$remote_sha" = "$last_sha" ]; then
    log "SKIP $key: unchanged at $remote_sha"
    return 0
  fi

  active_resp=$(curl -sf "$API/wiki/tasks?status=active" 2>/dev/null)
  if [ $? -ne 0 ]; then
    log "FAIL $key: could not reach deepwiki API to check in-flight tasks"
    return 1
  fi
  active_id=$(echo "$active_resp" | jq -r --arg o "$repo_owner" --arg r "$repo_name" \
    '.[] | select(.owner==$o and .repo==$r) | .id' 2>/dev/null)
  if [ -n "$active_id" ]; then
    log "SKIP $key: task $active_id already in flight, not touching its cache"
    return 1
  fi

  log "START $key: ${last_sha:-<none>} -> $remote_sha"

  # Force a real rebuild: drop the clone, the embedding db, AND the
  # wiki-page cache. The wiki-page cache alone would otherwise short-circuit
  # the POST below straight to from_cache=true with no work done at all.
  if ! docker exec "$CONTAINER" rm -rf \
    "/root/.adalflow/repo/${repo_owner}_${repo_name}" \
    "/root/.adalflow/repo/databases/${repo_owner}_${repo_name}.pkl"; then
    log "FAIL $key: could not clear clone/db inside container"
    return 1
  fi
  # A missing wiki cache 404s here - that just means there was none yet.
  curl -sf -X DELETE \
    "$API/wiki_cache?owner=${repo_owner}&repo=${repo_name}&repo_type=github&language=en" \
    >/dev/null 2>&1

  since=$(date +%s)

  # provider/model are required: the request schema defaults provider to
  # "google", and generator.json's default_provider does not reach this path.
  submit=$(curl -sf -X POST "$API/wiki/tasks" -H "Content-Type: application/json" \
    -d "{\"repo_url\": \"$repo_url\", \"owner\": \"$repo_owner\", \"repo\": \"$repo_name\", \"type\": \"github\", \"provider\": \"$PROVIDER\", \"model\": \"$MODEL\"}")
  if [ $? -ne 0 ]; then
    log "FAIL $key: POST /wiki/tasks failed"
    return 1
  fi
  task_id=$(echo "$submit" | jq -r '.task_id // empty')
  if [ -z "$task_id" ]; then
    log "FAIL $key: submit response had no task_id: $submit"
    return 1
  fi
  if [ "$(echo "$submit" | jq -r '.from_cache // false')" = "true" ]; then
    log "FAIL $key: submit returned from_cache=true right after we cleared the cache - not trusting it"
    return 1
  fi

  status="unknown"
  resp=""
  for ((i = 0; i < POLL_MAX; i++)); do
    resp=$(curl -sf "$API/wiki/tasks/$task_id" 2>/dev/null) || {
      sleep "$POLL_INTERVAL"
      continue
    }
    status=$(echo "$resp" | jq -r '.status // "unknown"')
    case "$status" in
    completed | failed) break ;;
    esac
    sleep "$POLL_INTERVAL"
  done

  if [ "$status" != "completed" ]; then
    err=$(echo "$resp" | jq -r '.error // "no error field"' 2>/dev/null)
    # Running out of poll budget does not stop the task - it keeps going and
    # finishes unrecorded. Say which happened so the log isn't read as a defeat.
    if [ "$status" = "failed" ]; then
      log "FAIL $key: task reported failed ($err)"
    else
      log "GAVE UP $key: still status=$status after $((POLL_MAX * POLL_INTERVAL / 3600))h; the task is STILL RUNNING and may yet succeed. Not recorded, so the next run redoes it - check the wiki cache before letting that happen."
    fi
    return 1
  fi

  # The initial embed pass never logs its non-empty/empty breakdown (that
  # only happens on a cache RE-load); wiki-page generation reloads the db it
  # just saved, so a healthy run always produces at least one such line in
  # this window. None found, or all zero, means the embeddings are unusable
  # even though the task reported success - the exact failure mode that once
  # stored 856 documents with zero usable embeddings.
  non_empty_max=$(docker logs --since "$since" "$CONTAINER" 2>&1 |
    grep -oP 'embeddings: \K[0-9]+(?= non-empty)' |
    sort -rn | head -1)
  non_empty_max=${non_empty_max:-0}

  if [ "$non_empty_max" -eq 0 ]; then
    log "FAIL $key: task completed but no non-empty embeddings observed in logs - treating as failure"
    return 1
  fi

  cache_check=$(curl -sf "$API/wiki_cache?owner=${repo_owner}&repo=${repo_name}&repo_type=github&language=en" 2>/dev/null)
  if [ -z "$cache_check" ] || [ "$cache_check" = "null" ]; then
    log "FAIL $key: task completed but wiki cache is still empty"
    return 1
  fi

  state_set "$key" "$remote_sha"
  log "OK $key: reindexed at $remote_sha (max non-empty embeddings seen: $non_empty_max)"
  return 0
}

# Named repos limit the run to those; no args means all of REPOS. A reindex is
# hours of CPU on the box serving quack's models, so being able to scope one
# beats hand-editing state (which would mark stale content as verified).
if [ $# -gt 0 ]; then
  selected=()
  for want in "$@"; do
    for repo_url in "${REPOS[@]}"; do
      [ "$(basename "$repo_url")" = "$want" ] && selected+=("$repo_url")
    done
  done
  if [ ${#selected[@]} -ne $# ]; then
    log "FAIL: unknown repo in: $*"
    log "known: $(for r in "${REPOS[@]}"; do printf '%s ' "$(basename "$r")"; done)"
    exit 2
  fi
  REPOS=("${selected[@]}")
fi

fail_count=0
for repo_url in "${REPOS[@]}"; do
  reindex_one "$repo_url" || fail_count=$((fail_count + 1))
done

if [ "$fail_count" -gt 0 ]; then
  log "Reindex complete with $fail_count repo(s) failed or skipped-with-warning"
else
  log "Reindex complete, all repos up to date"
fi

exit $((fail_count > 0 ? 1 : 0))
