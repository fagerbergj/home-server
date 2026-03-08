# Server Setup Guide

End-to-end setup for the home server. Follow phases in order.

## Phase 0 — Before You Build: Consolidate Media

Do this on your current PC before moving any drives to the server.

Current state:
- ~500GB of media split across the ADATA SSD and 1TB HDD
- 4TB Seagate arriving with the case

Steps:
1. Connect the 4TB drive to your current PC (USB enclosure or SATA)
2. Copy all media from both the ADATA and 1TB onto the 4TB:
   ```bash
   rsync -av /path/to/media/ /path/to/4tb/
   ```
3. Verify the copy looks complete before wiping anything
4. The ADATA and 1TB are now clear and ready for their new roles

Drive assignments going into the build:
- **256GB ADATA SSD** → OS drive (Linux Mint + Docker)
- **1TB HDD** → `/mnt/storage` (photos)
- **4TB HDD** → `/mnt/media` (Plex movies/TV)

---

## Phase 1 — OS Install (Linux Mint)

1. Boot the server from your existing Mint USB drive (spam F12 or DEL on POST to get boot menu)
2. Install Linux Mint:
   - Select the 256GB SSD as the install target
   - Use "Erase disk and install" — this is a dedicated machine
   - Set a strong password, enable auto-login is fine since it's headless
3. After install, remove USB and reboot

Update system after first boot:
```bash
sudo apt update && sudo apt upgrade -y
sudo reboot
```

### Enable SSH

Do this while you still have a monitor plugged in — everything after this can be done remotely.

```bash
sudo apt install -y openssh-server
sudo systemctl enable ssh
sudo systemctl start ssh
```

Find the server's local IP:
```bash
ip addr show | grep "inet " | grep -v 127.0.0.1
```

From your main PC, connect:
```bash
ssh jason@<server-ip>
```

### SSH Key Authentication

Avoid typing a password every time:
```bash
# Run on your main PC
ssh-copy-id jason@<server-ip>
```

If you don't have an SSH key yet:
```bash
ssh-keygen -t ed25519
```

**Everything from this point forward can be done via SSH from your main PC. Unplug the monitor.**

---

## Phase 2 — Mount Drives

Find drive UUIDs:
```bash
lsblk -f
```

Add entries to `/etc/fstab` for the 1TB and 4TB drives:
```
UUID=<4tb-uuid>     /mnt/plex01      ext4  defaults  0  2
UUID=<1tb-uuid>     /mnt/personal01  ext4  defaults  0  2
```

Format drives if new (skip if already formatted):
```bash
sudo mkfs.ext4 /dev/sdX   # replace sdX with correct device
```

Mount and verify:
```bash
sudo mkdir -p /mnt/plex01 /mnt/personal01
sudo mount -a
lsblk
```

### Service Users

Create dedicated system users for each service — no login, no home dir. Each container runs as its own user with access only to what it needs.

```bash
# Create service users
sudo useradd -r -s /sbin/nologin plex
sudo useradd -r -s /sbin/nologin immich
sudo useradd -r -s /sbin/nologin minecraft

# Create a shared media group for drive access
sudo groupadd media
sudo usermod -aG media plex
sudo usermod -aG media immich
```

Note the UIDs — you'll need them for the compose files:
```bash
id plex
id immich
id minecraft
```

### Folder Structure and Permissions

```bash
# Plex drive
sudo mkdir -p /mnt/plex01/movies
sudo mkdir -p /mnt/plex01/tv
sudo chown -R plex:media /mnt/plex01
sudo chmod -R 775 /mnt/plex01

# Personal drive
sudo mkdir -p /mnt/personal01/photos
sudo chown -R immich:media /mnt/personal01
sudo chmod -R 775 /mnt/personal01
```

Verify:
```bash
ls -la /mnt/plex01
ls -la /mnt/personal01
```

### Checking Drive Health

Check drive health periodically with smartmontools:
```bash
sudo apt install -y smartmontools

# Quick health check
sudo smartctl -H /dev/sda

# Full drive info
sudo smartctl -a /dev/sda
```

Replace `/dev/sda` with the correct device — use `lsblk` to find device names.

### Checking Disk Usage

```bash
df -h
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

Linux Mint is Debian-based so we use the Debian Docker repo:

```bash
# Install dependencies
sudo apt install -y ca-certificates curl gnupg

# Add Docker's official GPG key and repo
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian bookworm stable" | \
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

Generate an SSH key on the server:
```bash
ssh-keygen -t ed25519 -C "home-server"
cat ~/.ssh/id_ed25519.pub
```

Copy the output and add it to GitHub: **Settings > SSH and GPG keys > New SSH key**

Verify it works:
```bash
ssh -T git@github.com
```

You should see: `Hi fagerbergj! You've successfully authenticated...`

Clone this repo:
```bash
mkdir -p ~/workspace
cd ~/workspace
git clone git@github.com:fagerbergj/home-server.git
```

---

## Phase 6 — Claude Code

Install Node.js (required for Claude Code):
```bash
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt install -y nodejs
```

Install Claude Code:
```bash
npm install -g @anthropic-ai/claude-code
```

Authenticate via API key — get one from console.anthropic.com:
```bash
echo 'export ANTHROPIC_API_KEY=your-key-here' >> ~/.bashrc
source ~/.bashrc
```

Verify:
```bash
claude --version
```

---

## Phase 7 — Services (Docker Compose)

See individual service directories:

- [`plex/`](plex/) — Plex Media Server
- [`minecraft/`](minecraft/) — Minecraft Server
- [`photos/`](photos/) — Immich Photo Storage
- [`qbittorrent/`](qbittorrent/) — qBittorrent (downloads straight to `/mnt/plex01`)

> These will be set up in order. See each directory for its own README.

---

## Phase 8 — Networking

See [`networking/`](networking/) for the full networking setup. Summary:

1. Set a DHCP reservation in the ASUS router so the server always gets the same local IP
2. Enable ASUS DDNS: WAN > DDNS > pick a hostname (e.g. `yourname.asuscomm.com`)
4. Forward ports 80, 443, and 25565 on your router to the server's static IP
5. Start Nginx Proxy Manager and configure proxy hosts for Plex and Immich
6. Install the Immich mobile app and point it at `https://photos.yourname.asuscomm.com` for automatic photo backup
7. Friends connect to Minecraft via `yourname.asuscomm.com:25565`
