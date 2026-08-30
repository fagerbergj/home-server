#!/bin/bash
# jaison Phase 5 — Docker (no GPU toolkit: the Vulkan image uses /dev/dri passthrough)
set -euo pipefail

echo "=== Phase 5: Docker ==="
echo ""

# --- Docker ---
sudo apt install -y ca-certificates curl gnupg make

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu noble stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

sudo usermod -aG docker "$USER"

echo ""
echo "=== Phase 5 complete ==="
echo "NOTE: Log out and back in (or run 'newgrp docker') for Docker group membership to take effect."
