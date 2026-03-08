#!/bin/bash
# Phase 5 — GitHub SSH Setup and Repo Clone
set -euo pipefail

echo "=== Phase 5: GitHub ==="
echo ""

# --- Generate SSH key ---
if [ ! -f ~/.ssh/id_ed25519 ]; then
    ssh-keygen -t ed25519 -C "home-server" -f ~/.ssh/id_ed25519 -N ""
    echo "SSH key generated."
else
    echo "SSH key already exists, skipping generation."
fi

echo ""
echo "Add this public key to GitHub (Settings > SSH and GPG keys > New SSH key):"
echo ""
cat ~/.ssh/id_ed25519.pub
echo ""
read -rp "Press ENTER once you've added the key to GitHub..."

# --- Verify ---
echo ""
echo "Verifying GitHub connection..."
ssh -T git@github.com || true

# --- Clone repo ---
echo ""
mkdir -p ~/workspace
cd ~/workspace

if [ ! -d ~/workspace/home-server ]; then
    git clone git@github.com:fagerbergj/home-server.git
    echo "Repo cloned to ~/workspace/home-server"
else
    echo "Repo already exists at ~/workspace/home-server, skipping clone."
fi

echo ""
echo "=== Phase 5 complete ==="
