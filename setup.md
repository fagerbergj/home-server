# Server Setup Guide

End-to-end setup for the home server. Follow phases in order.

## Phase 1 — OS Install (Linux Mint)

1. Download Linux Mint (latest LTS) from linuxmint.com — choose the Cinnamon edition
2. Flash to a USB drive using Balena Etcher or `dd`
3. Boot the server from USB (spam F12 or DEL on POST to get boot menu)
4. Install Linux Mint:
   - Select the 256GB SSD as the install target
   - Use "Erase disk and install" — this is a dedicated machine
   - Set a strong password, enable auto-login is fine since it's headless
5. After install, remove USB and reboot

Update system after first boot:
```bash
sudo apt update && sudo apt upgrade -y
sudo reboot
```

---

## Phase 2 — Mount Drives

Find drive UUIDs:
```bash
lsblk -f
```

Add entries to `/etc/fstab` for the 1TB and 4TB drives:
```
UUID=<4tb-uuid>   /mnt/media    ext4  defaults  0  2
UUID=<1tb-uuid>   /mnt/storage  ext4  defaults  0  2
```

Format drives if new (skip if already formatted):
```bash
sudo mkfs.ext4 /dev/sdX   # replace sdX with correct device
```

Mount and verify:
```bash
sudo mkdir -p /mnt/media /mnt/storage
sudo mount -a
lsblk
```

---

## Phase 3 — NVIDIA Drivers

Install the recommended NVIDIA driver:
```bash
sudo apt install -y ubuntu-drivers-common
sudo ubuntu-drivers autoinstall
sudo reboot
```

Verify after reboot:
```bash
nvidia-smi
```

You should see the GTX 1070 Ti listed with driver version and VRAM.

---

## Phase 4 — Docker

```bash
# Install dependencies
sudo apt install -y ca-certificates curl gnupg

# Add Docker's official GPG key and repo
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Allow your user to run Docker without sudo
sudo usermod -aG docker $USER
newgrp docker
```

Install NVIDIA Container Toolkit (allows Docker containers to use the GPU):
```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt update
sudo apt install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

Verify GPU is accessible from Docker:
```bash
docker run --rm --gpus all nvidia/cuda:12.0-base-ubuntu22.04 nvidia-smi
```

---

## Phase 5 — GitHub

Install GitHub CLI and authenticate:
```bash
sudo apt install -y gh
gh auth login
```

Clone this repo:
```bash
mkdir -p ~/workspace
cd ~/workspace
gh repo clone fagerbergj/home-server
```

---

## Phase 6 — Services (Docker Compose)

See individual service directories:

- [`plex/`](plex/) — Plex Media Server
- [`minecraft/`](minecraft/) — Minecraft Server
- [`photos/`](photos/) — Immich Photo Storage

> These will be set up in order. See each directory for its own README.

---

## Phase 7 — Networking

> To be documented — covers:
> - Static local IP for the server
> - Port forwarding on the router (Plex, Minecraft)
> - Firewall (ufw) rules
> - Optional: remote access / VPN
