#!/bin/bash
# Called by cron — emails if any monitored drive exceeds 90% usage
set -euo pipefail

THRESHOLD=90
EMAIL="jf.fagerberg@gmail.com"
HOSTNAME=$(hostname)

for mount in /mnt/plex01 /mnt/personal01; do
    usage=$(df "$mount" 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%')
    if [ -n "$usage" ] && [ "$usage" -ge "$THRESHOLD" ]; then
        echo -e "Subject: [${HOSTNAME}] Disk warning: ${mount} is ${usage}% full\n\n$(df -h "$mount")" \
            | msmtp "$EMAIL"
    fi
done
