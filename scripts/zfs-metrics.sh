#!/bin/bash
# Cron (every 5 min): pool usage for node-exporter's textfile collector.
# df on a pool root misses child datasets and snapshots; `zfs list` used/avail covers both.
set -euo pipefail

dir="$(dirname "$(realpath "$0")")/../monitoring/node-textfile"
mkdir -p "$dir"
zfs list -Hp -d 0 -o name,used,avail,mountpoint | awk -F'\t' '{
    printf "zfs_pool_used_bytes{pool=\"%s\",mountpoint=\"%s\"} %s\n", $1, $4, $2
    printf "zfs_pool_avail_bytes{pool=\"%s\",mountpoint=\"%s\"} %s\n", $1, $4, $3
}' > "$dir/zfs.prom.tmp"
mv "$dir/zfs.prom.tmp" "$dir/zfs.prom"   # atomic, so a scrape never reads a half-written file
