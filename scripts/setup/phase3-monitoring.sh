#!/bin/bash
# Phase 3 — Monitoring Tools (btop, nvtop)
set -euo pipefail

echo "=== Phase 3: Monitoring Tools ==="
echo ""

sudo apt install -y btop nvtop

echo ""
echo "=== Phase 3 monitoring tools installed ==="
echo "  btop   — run 'btop' for CPU/memory/disk/network overview"
echo "  nvtop  — run 'nvtop' for GPU usage and VRAM"
