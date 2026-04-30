#!/bin/bash
# Phase 4 — Memory tuning for the ZFS + Docker + LLM workload.
#
# Caps ZFS ARC and lowers swappiness so that loading large mmap'd files
# (Ollama models from /mnt/cache, big container images, etc.) doesn't
# evict process memory to swap.
#
# Why ARC needs a cap on this server:
#   - Default ARC ceiling is ~50% of RAM (~24 GB on a 48 GB box).
#   - ARC doesn't release memory promptly under pressure from non-ZFS
#     consumers (kernel page cache for ext4 / mmap'd files).
#   - The result: loading a 24 GB Ollama model from /mnt/cache (ext4)
#     hammers swap because the kernel can't reclaim ARC fast enough.
#
# 16 GB ARC is plenty for media-mostly workloads (Plex/torrents are
# network-bound, not cache-bound). Personal pool sees small writes that
# don't benefit from a giant ARC either.
set -euo pipefail

ARC_MAX_BYTES=$((16 * 1024 * 1024 * 1024))
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
echo "vm.swappiness=$SWAPPINESS" | sudo tee /etc/sysctl.d/99-swappiness.conf >/dev/null
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
echo "If swap is still in use from before tuning, drain it:"
echo "  sudo swapoff -a && sudo swapon -a"
