#!/bin/bash
# jaison firewall: SSH from the LAN, llama-swap only from the media box.
set -euo pipefail
MEDIA_BOX=${MEDIA_BOX:-192.168.50.186}
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 192.168.50.0/24 to any port 22 proto tcp
sudo ufw allow from "$MEDIA_BOX" to any port 11436 proto tcp   # llm-swap
sudo ufw enable
sudo ufw status verbose
