#!/bin/bash
# Phase 4 — Memory tuning for the ZFS + Docker + LLM workload.
#
# Caps ZFS ARC and lowers swappiness so that loading large files
# (GGUF weights from /mnt/cache/huggingface, big container images, etc.)
# doesn't evict process memory to swap.
#
# Why ARC needs a cap on this server:
#   - Default ARC ceiling is ~50% of RAM (~31 GB of the 62 GB here).
#   - ARC doesn't release memory promptly under pressure from non-ZFS
#     consumers (kernel page cache for ext4 reads).
#   - The result: loading a large GGUF from /mnt/cache (ext4) hammers
#     swap because the kernel can't reclaim ARC fast enough.
#
# 24 GB: since 2026-08-30 the big models run on jaison, so this box's RAM
# only hosts the 3090's llama-swap (embedder + 9B, ~12 GB in VRAM, little
# host RAM), Plex, immich and the rest. The old 8 GB cap existed because
# --no-mmap llama-server processes here competed with ARC and swapped model
# pages out (decode fell to disk speed); that pressure is gone. Leave ~30 GB
# for containers and page cache on the 64 GB box.
set -euo pipefail

ARC_MAX_BYTES=$((24 * 1024 * 1024 * 1024))
SWAPPINESS=10

echo "=== Phase 4: Memory tuning ==="
echo ""

# ---------------------------------------------------------------------------
# ZFS ARC cap
# ---------------------------------------------------------------------------

echo "Setting ZFS ARC max to $((ARC_MAX_BYTES / 1024 / 1024 / 1024)) GB (live)..."
echo "$ARC_MAX_BYTES" | sudo tee /sys/module/zfs/parameters/zfs_arc_max >/dev/null

echo "Persisting ARC cap to /etc/modprobe.d/zfs.conf..."
echo "options zfs zfs_arc_max=$ARC_MAX_BYTES" | sudo tee /etc/modprobe.d/zfs.conf >/dev/null
sudo update-initramfs -u >/dev/null
echo "  ARC cap persisted across reboots."

# Force ARC to shrink to new cap immediately so downstream load tests are
# representative — ARC otherwise shrinks lazily under pressure.
echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null

# ---------------------------------------------------------------------------
# Swappiness
# ---------------------------------------------------------------------------

echo ""
echo "Setting vm.swappiness to $SWAPPINESS..."
# One file owns swappiness. Earlier duplicates (99-swappiness.conf,
# 99-sysctl.conf, an entry in sysctl.conf) silently overrode this one.
echo "vm.swappiness=$SWAPPINESS" | sudo tee /etc/sysctl.d/99-llm-swap.conf >/dev/null
sudo sysctl --system | grep swappiness | tail -1

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "=== Phase 4 tuning complete ==="
echo ""
awk '/^c_max/ {printf "  ARC max: %.1f GB\n", $3/1024/1024/1024} /^size/ {printf "  ARC now: %.1f GB\n", $3/1024/1024/1024}' /proc/spl/kstat/zfs/arcstats
echo "  vm.swappiness: $(cat /proc/sys/vm/swappiness)"
echo ""
echo "Swap in use from before tuning drains on its own as pages are touched."
echo "Only force it when 'free -h' shows swap used < available RAM, or the"
echo "swapoff will fail or OOM pulling everything back at once:"
echo "  sudo swapoff -a && sudo swapon -a"
