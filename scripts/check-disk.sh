#!/bin/bash
# Called by cron — emails if a monitored mount crosses its threshold.
# / is 85%: the DRAM-less OS SSD hung at 99% full on 2026-10-13.
set -euo pipefail

EMAIL="jf.fagerberg@gmail.com"
HOSTNAME=$(hostname)

for spec in /:85 /mnt/media:90 /mnt/personal:90; do
    mount=${spec%:*} threshold=${spec##*:}
    # Pools via zfs: df on a pool root misses child datasets and snapshots.
    if read -r used avail < <(zfs list -Hp -o used,avail "$mount" 2>/dev/null); then
        usage=$((used * 100 / (used + avail)))
    else
        usage=$(df "$mount" 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%')
    fi
    if [ -n "$usage" ] && [ "$usage" -ge "$threshold" ]; then
        echo -e "Subject: [${HOSTNAME}] Disk warning: ${mount} is ${usage}% full\n\n$(df -h "$mount")" \
            | msmtp "$EMAIL"
    fi
done
