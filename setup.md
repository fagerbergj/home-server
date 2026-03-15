# Server Setup Guide

End-to-end setup for the home server. Follow phases in order.

## Phase 0 — Before You Build: Consolidate Media

Do this on your current PC before moving any drives to the server.

Current state:
- ~500GB of media split across the ADATA SSD (`/mnt/ADATASSD`) and 1TB WD HDD (`/mnt/HDD`)
- ~18GB of photos on `/media/jason/Removable Drive/Pictures` — safe, not moving to server until after RAID 1 is set up
- 4TB Seagate, 1TB Seagate, and Define R5 case purchased and arriving
- StarTech USB-C to SATA adapter purchased for connecting the 4TB externally

Steps:
1. Connect the 4TB drive to your current PC using the StarTech USB-C to SATA adapter
2. Copy all media from the ADATA onto the 4TB:
   ```bash
   rsync -av /mnt/ADATASSD/Videos/ /path/to/4tb/
   ```
3. Verify the copy looks complete before wiping anything
4. The ADATA and 1TB WD are now clear and ready for their new roles

Photos will be copied to the server over SSH after RAID 1 is set up — see Phase 4.

Drive assignments going into the build:
- **480GB ADATA SSD** → OS drive (Ubuntu Server 24.04 LTS + Docker)
- **1TB Seagate HDD** (new) → RAID 1 primary for `/mnt/personal01`
- **1TB WD HDD** (from main PC) → RAID 1 secondary for `/mnt/personal01`
- **4TB Seagate HDD** → `/mnt/plex01` (Plex movies/TV)

---

## Phase 1 — OS Install (Ubuntu Server 24.04 LTS)

1. Boot the server from your Ubuntu Server USB drive (spam F12 or DEL on POST to get boot menu)
2. Install Ubuntu Server:
   - Select the 480GB SSD as the install target
   - Use the entire disk — this is a dedicated machine
   - Set a strong password
   - Enable SSH when the installer offers it
3. After install, remove USB and boot into the OS

### Static IP & Router Config

Do this before the first system update reboot — the server is on the network now and its MAC address is visible in the router.

See [`networking/setup.md`](networking/setup.md) — Phase 1 section.

### Update & Reboot

```bash
sudo apt update && sudo apt upgrade -y
sudo reboot
```

The server will come back on its reserved static IP.

### Enable SSH

If you didn't enable SSH during install:

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
ssh jason-server@<server-ip>
```

### SSH Key Authentication

Avoid typing a password every time. If you don't have an SSH key yet, generate one first:
```bash
ssh-keygen -t ed25519
```

Then copy it to the server:
```bash
# Run on your main PC
ssh-copy-id jason-server@<server-ip>
```

### Firewall

```bash
scripts/setup/phase1-firewall.sh
```

**Everything from this point forward can be done via SSH from your main PC. Unplug the monitor.**

---

## Phase 2 — GitHub

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

### Root .env

If you already have a filled-out `.env` on your main PC, copy it over:
```bash
# Run on your main PC
scp ~/workspace/home-server/.env jason-server@<server-ip>:~/workspace/home-server/.env
```

Otherwise copy the example and fill in your values:
```bash
cp ~/workspace/home-server/.env.example ~/workspace/home-server/.env
```

See `.env.example` for all required variables and where to get them. This file is gitignored. Setup scripts that need it will say so — source it before running them:
```bash
source ~/workspace/home-server/.env
```

---

### Monitoring Tools
> **Script:** `scripts/setup/phase3-monitoring.sh`

<details>
<summary>Manual steps</summary>

```bash
sudo apt install -y btop nvtop
```

</details>

Run them:
```bash
btop    # CPU, memory, disk, and network at a glance
nvtop   # GPU utilization and VRAM usage
```

---

## Phase 4 — Mount Drives
> **Script:** `scripts/setup/phase4-drives.sh` — run this instead of the manual steps below.
>
> ⚠️ **If you completed Phase 0**, plex01 already has your media — **do not run the script**, it will format the drive and wipe everything. Use the manual steps below and skip the format step for plex01.

<details>
<summary>Manual steps</summary>

Find drive UUIDs:
```bash
lsblk -f
```

### Mount plex01

> **If you completed Phase 0:** the 4TB drive already has your media — skip the format step and go straight to mounting by UUID.

Format the 4TB drive (**skip if coming from Phase 0**):
```bash
sudo mkfs.ext4 /dev/sdX   # replace sdX with correct device — use lsblk to find it
```

Get the UUID (run this regardless):
```bash
sudo blkid /dev/sdX
```

Add to `/etc/fstab`:
```
UUID=<4tb-uuid>   /mnt/plex01   ext4   defaults   0   2
```

```bash
sudo mkdir -p /mnt/plex01
sudo mount -a
```

### Mount plex02 (optional overflow drive)

If the 640GB Hitachi drive is present, the script detects it automatically and mounts it as `/mnt/plex02`. Use this for non-critical, re-downloadable Plex media only — the drive has high hours.

If running manually:
```bash
sudo mkfs.ext4 /dev/sdX1   # replace with correct device
sudo mkdir -p /mnt/plex02
# Get UUID:
sudo blkid /dev/sdX1
# Add to /etc/fstab:
UUID=<uuid>   /mnt/plex02   ext4   defaults   0   2
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
sudo usermod -aG plex-rw jason-server  # manage plex drive directly
sudo usermod -aG plex-ro plex          # plex reads media

sudo usermod -aG personal-rw immich    # immich writes photos
sudo usermod -aG personal-rw jason-server  # manage personal drive directly
```

### Folder Structure and Permissions

```bash
sudo apt install -y acl
```

```bash
# Plex drive
sudo mkdir -p /mnt/plex01/movies
sudo mkdir -p /mnt/plex01/shows
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

</details>

### Copy Photos to Server

Once RAID 1 is set up and `/mnt/personal01` is mounted, copy photos from your main PC over SSH:

```bash
# Run on your main PC
rsync -av --progress "/media/jason/Removable Drive/Pictures/" jason-server@<server-ip>:/mnt/personal01/photos/
```

Run the IDs script to look up UIDs/GIDs and automatically update the compose files:
```bash
scripts/setup/phase4-ids.sh
```

### RAID Failure Alerts and Disk Monitoring

Run the alerts setup script — it configures msmtp, mdadm email alerts, and a daily disk usage check:

```bash
source ~/workspace/home-server/.env
scripts/setup/phase4-alerts.sh
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

## Phase 5 — Docker
> **Script:** `scripts/setup/phase5-docker.sh`

<details>
<summary>Manual steps</summary>

```bash
# Install dependencies
sudo apt install -y ca-certificates curl gnupg

# Add Docker's official GPG key and repo
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu noble stable" | \
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

</details>

Verify GPU is accessible from Docker:
```bash
docker run --rm --gpus all nvidia/cuda:12.0-base-ubuntu24.04 nvidia-smi
```

---

## Phase 6 — Nginx Proxy Manager

Router config and firewall were handled in Phase 1. This phase starts NPM and configures proxy hosts.

See [`networking/setup.md`](networking/setup.md) — Phase 6 section for full details.

---

## Phase 7 — Services (Docker Compose)

Start services in this order — see each directory's `setup.md` for details:

1. [`plex/setup.md`](plex/setup.md)
2. [`minecraft/setup.md`](minecraft/setup.md)
3. [`photos/setup.md`](photos/setup.md)
4. [`qbittorrent/setup.md`](qbittorrent/setup.md)
5. [`llm/setup.md`](llm/setup.md)
6. [`watchtower/setup.md`](watchtower/setup.md) — start this last
