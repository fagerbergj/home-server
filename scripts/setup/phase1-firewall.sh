#!/bin/bash
# Configures ufw firewall rules for all server services
set -euo pipefail

sudo ufw allow 80/tcp    # HTTP (NPM)
sudo ufw allow 443/tcp   # HTTPS (NPM)
sudo ufw allow 25565/tcp # Minecraft
# Port 3000 (Open WebUI) and 11436 (llm-swap API) are intentionally not opened — public traffic goes through NPM on 443; admin access is tailnet-only

sudo ufw enable
sudo ufw status
