#!/bin/bash
# Phase 5 — Docker
set -euo pipefail

echo "=== Phase 5: Docker ==="
echo ""

# --- Docker ---
sudo apt install -y ca-certificates curl gnupg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu noble stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

sudo usermod -aG docker "$USER"

# ROCm containers use /dev/kfd + /dev/dri device passthrough — no extra toolkit needed.
# GPU access is configured per-service in each docker-compose.yml.

echo ""
echo "Verifying GPU is accessible from Docker..."
docker run --rm --device=/dev/kfd --device=/dev/dri \
  --group-add video --group-add render \
  rocm/rocm-terminal rocm-smi

echo ""
echo "=== Phase 5 complete ==="
echo "NOTE: Log out and back in (or run 'newgrp docker') for Docker group membership to take effect."
