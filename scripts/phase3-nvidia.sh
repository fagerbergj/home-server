#!/bin/bash
# Phase 3 — NVIDIA Drivers
set -euo pipefail

echo "=== Phase 3: NVIDIA Drivers ==="
echo ""

sudo apt install -y ubuntu-drivers-common
sudo ubuntu-drivers autoinstall

echo ""
echo "=== Phase 3 complete ==="
echo "Rebooting in 5 seconds — verify with 'nvidia-smi' after reboot..."
sleep 5
sudo reboot
