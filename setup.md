# Server Setup Guide

End-to-end setup for the home server. Follow phases in order.

## Phase 0 — Before You Build: Consolidate Media

Do this on your current PC before moving any drives to the server.

Current state:
- ~500GB of media split across the ADATA SSD (`/mnt/ADATASSD`) and 1TB WD HDD (`/mnt/HDD`)
- ~18GB of photos on `/media/jason/Removable Drive/Pictures`
- 4TB Seagate, 1TB Seagate, and Define R5 case purchased and arriving
- StarTech USB-C to SATA adapter purchased for connecting the 4TB externally

Steps:
1. Connect the 4TB drive to your current PC using the StarTech USB-C to SATA adapter
2. Copy all media from the ADATA onto the 4TB:
   ```bash
   rsync -av /mnt/ADATASSD/Videos/ /path/to/4tb/
   ```
3. Copy photos off the removable drive onto the 4TB as well — they'll need to move temporarily since RAID 1 setup wipes both drives:
   ```bash
   rsync -av "/media/jason/Removable Drive/Pictures/" /path/to/4tb/photos-backup/
   ```
4. Verify both copies look complete before wiping anything
5. The ADATA and 1TB WD are now clear and ready for their new roles

Once the server is built and RAID 1 is set up, copy photos from the 4TB back to `/mnt/personal01`:
```bash
rsync -av /mnt/plex01/photos-backup/ /mnt/personal01/photos/
```

Then delete the temporary backup from the 4TB:
```bash
rm -rf /mnt/plex01/photos-backup/
```

Drive assignments going into the build:
- **256GB ADATA SSD** → OS drive (Linux Mint + Docker)
- **1TB Seagate HDD** (new) → RAID 1 primary for `/mnt/personal01`
- **1TB WD HDD** (from main PC) → RAID 1 secondary for `/mnt/personal01`
- **4TB Seagate HDD** → `/mnt/plex01` (Plex movies/TV)

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

### Mount plex01

Format the 4TB drive:
```bash
sudo mkfs.ext4 /dev/sdX   # replace sdX with correct device — use lsblk to find it
```

Add to `/etc/fstab`:
```
UUID=<4tb-uuid>   /mnt/plex01   ext4   defaults   0   2
```

```bash
sudo mkdir -p /mnt/plex01
sudo mount -a
```

### Set Up RAID 1 for personal01

Install mdadm:
```bash
sudo apt install -y mdadm
```

Identify the two 1TB drives:
```bash
lsblk
```

Create the RAID 1 array — replace `sdX` and `sdY` with your two 1TB drives:
```bash
sudo mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/sdX /dev/sdY
```

> **Drive order matters:** put the new Seagate first (`sdX`) and the old WD second (`sdY`) — the new drive is the primary.

Monitor the initial sync (takes ~2 hours for 1TB):
```bash
watch cat /proc/mdstat
```

Format and mount once sync completes:
```bash
sudo mkfs.ext4 /dev/md0
sudo mkdir -p /mnt/personal01
sudo mount /dev/md0 /mnt/personal01
```

Save the RAID config and add to fstab:
```bash
sudo mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf
sudo update-initramfs -u

# Get the UUID of the md0 array
sudo blkid /dev/md0

# Add to /etc/fstab
UUID=<md0-uuid>   /mnt/personal01   ext4   defaults   0   2
```

Verify:
```bash
sudo mdadm --detail /dev/md0
```

You should see both drives listed as `active sync`.

### Service Users

Create dedicated system users for each service — no login, no home dir. Each container runs as its own user with access only to what it needs.

```bash
# Create service users
sudo useradd -r -s /sbin/nologin plex
sudo useradd -r -s /sbin/nologin immich
sudo useradd -r -s /sbin/nologin minecraft
sudo useradd -r -s /sbin/nologin qbittorrent

# Create groups
sudo groupadd plex-rw
sudo groupadd plex-ro
sudo groupadd personal-rw
sudo groupadd personal-ro

# Assign groups
sudo usermod -aG plex-rw qbittorrent   # downloads to plex drive
sudo usermod -aG plex-rw jason         # manage plex drive directly
sudo usermod -aG plex-ro plex          # plex reads media

sudo usermod -aG personal-rw immich    # immich writes photos
sudo usermod -aG personal-rw jason     # manage personal drive directly
```

Note the UIDs and GIDs — you'll need them for the compose files:
```bash
id plex
id immich
id minecraft
id qbittorrent
getent group plex-rw
getent group plex-ro
getent group personal-rw
```

### Folder Structure and Permissions

```bash
sudo apt install -y acl
```

```bash
# Plex drive
sudo mkdir -p /mnt/plex01/movies
sudo mkdir -p /mnt/plex01/tv
sudo chown -R root:plex-rw /mnt/plex01
sudo chmod -R 2775 /mnt/plex01  # setgid — new files inherit plex-rw group
sudo setfacl -R -m g:plex-ro:rx /mnt/plex01  # plex-ro gets read-only

# Personal drive
sudo mkdir -p /mnt/personal01/photos
sudo chown -R root:personal-rw /mnt/personal01
sudo chmod -R 2775 /mnt/personal01  # setgid — new files inherit personal-rw group
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
