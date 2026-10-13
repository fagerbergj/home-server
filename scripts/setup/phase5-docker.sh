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

# NVIDIA container toolkit: services opt in with `runtime: nvidia` in their compose.
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt update
sudo apt install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

echo ""
echo "Verifying GPU is accessible from Docker..."
docker run --rm --runtime=nvidia -e NVIDIA_VISIBLE_DEVICES=all \
  nvidia/cuda:12.8.1-base-ubuntu24.04 nvidia-smi

# Weekly prune (Sun 04:00): build cache older than a week and dangling images only.
# Never `image prune -a`: llm-swap's on-demand runtime images have no container until requested.
PRUNE='docker builder prune -f --filter until=168h >/dev/null && docker image prune -f >/dev/null'
if ! { crontab -l 2>/dev/null || true; } | grep -qF "docker builder prune"; then
    ({ crontab -l 2>/dev/null || true; }; echo "0 4 * * 0 $PRUNE") | crontab -
fi

echo ""
echo "=== Phase 5 complete ==="
echo "NOTE: Log out and back in (or run 'newgrp docker') for Docker group membership to take effect."
