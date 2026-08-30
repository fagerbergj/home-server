#!/bin/bash
# Pull the working model set from the media box's archive onto the local NVMe.
# Copy, never mount: mmap over NFS turns every page fault into a network round trip.
set -euo pipefail
SRC=${SRC:-jason-server@192.168.50.186:/mnt/media/models/huggingface/}
DST=${DST:-/mnt/cache/huggingface/}
rsync -aH --info=progress2 --partial "$SRC" "$DST"
