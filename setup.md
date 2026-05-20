# Server Setup Guide

End-to-end setup for the home server. Follow phases in order.

## Phase 0 — Before You Build: Drive Inventory

This guide assumes the target hardware in `hardware.md`:

- **500GB NVMe (M.2)** → OS drive (`nvme0n1`) — Ubuntu Server 24.04 LTS + Docker
- **4× 26TB Seagate Exos `ST26000NM000C`** → `media` ZFS pool (RAIDZ2) at `/mnt/media`
- **2× 8TB Dell `J7W80`** → `personal` ZFS pool (2-way mirror) at `/mnt/personal`
- **LSI 9300-16i HBA (IT mode)** → all six HDDs hang off this card, in PCIEX1_4

Before starting, burn-in the new HDDs (`badblocks -wsv` for recertified, `smartctl -t long` for new) and pull SMART output for each. Any reallocated/pending/UDMA-CRC errors → RMA before pool creation. See `hardware_upgrades.md` for the full burn-in protocol.

> **Build history:** the server originally ran a mixed mdadm RAID 1 + bare-ext4 layout across an ADATA SSD, a 4TB Seagate Barracuda (DM-SMR — unsafe in any RAID), a 640GB Hitachi (41k hours), and 2× 1TB drives. It was migrated to the all-ZFS layout above in April 2026; see `hardware_upgrades.md` for the migration steps and rationale.

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
ssh jason-server@192.168.50.186
```

### SSH Key Authentication

Avoid typing a password every time. If you don't have an SSH key yet, generate one first:
```bash
ssh-keygen -t ed25519
```

Then copy it to the server:
```bash
# Run on your main PC
ssh-copy-id jason-server@192.168.50.186
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
scp ~/workspace/home-server/.env jason-server@192.168.50.186:~/workspace/home-server/.env
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

## Phase 3 — AMD GPU Drivers (ROCm)

The in-tree `amdgpu` kernel driver doesn't support RDNA 4 (gfx1201 / R9700). Install the out-of-tree DKMS module + ROCm stack from AMD's repo.

### Install ROCm

```bash
# Download the amdgpu-install meta-package (check https://repo.radeon.com/amdgpu-install/ for latest)
curl -fsSL https://repo.radeon.com/amdgpu-install/latest/ubuntu/jammy/amdgpu-install_7.2.3.70203-1_all.deb \
  -o /tmp/amdgpu-install.deb
sudo apt install -y /tmp/amdgpu-install.deb

# Install ROCm + DKMS kernel module (DKMS builds the out-of-tree driver for gfx1201)
sudo amdgpu-install --usecase=rocm,dkms

# Add your user to the render and video groups for GPU access
sudo usermod -aG render,video "$USER"

sudo reboot
```

### Verify

```bash
rocm-smi
nvtop
```

You should see the R9700 listed with temperature, VRAM, and clock info.

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

## Phase 4 — Build ZFS Pools

Install ZFS tooling first:
```bash
sudo apt update
sudo apt install -y zfsutils-linux jq smartmontools
zfs version   # must be >= 2.2
```

If any HDDs were previously used (recertified Exos, drives migrated from another box), wipe their existing filesystem/RAID/GPT signatures so `zpool create` can claim them whole-disk without `-f`:
```bash
sudo bash scripts/setup/phase0-prep-drives.sh
```

Detect and assign drives:
```bash
sudo bash scripts/setup/phase4-detect-drives.sh
```

This buckets non-OS drives by size — 4 in the 24–28 TB range become `media_pool`, 2 in the 7–9 TB range become `personal_pool` — and resolves each to its `/dev/disk/by-id/{ata,scsi-SATA}-*` symlink (whichever the kernel emits; HBA-attached drives go through mpt3sas as `scsi-SATA_*`). Output is written to `scripts/setup/drives.json`.

Review before proceeding:
```bash
cat scripts/setup/drives.json
```

Then build the pools, datasets, users, groups, and permissions:
```bash
sudo bash scripts/setup/phase4-drives.sh
```

The script is idempotent — re-running it is safe. It prints the PUID/PGID values you'll need for docker-compose at the end.

<details>
<summary>Manual steps</summary>

### Build the media pool (RAIDZ2, 4× 26TB)

```bash
ls -l /dev/disk/by-id/ | grep -i ST26000

sudo zpool create -o ashift=12 \
  -O compression=lz4 \
  -O atime=off \
  -O xattr=sa \
  -O acltype=posixacl \
  -O recordsize=1M \
  -O mountpoint=/mnt/media \
  media raidz2 \
    /dev/disk/by-id/scsi-SATA_ST26000NM000C-... \
    /dev/disk/by-id/scsi-SATA_ST26000NM000C-... \
    /dev/disk/by-id/scsi-SATA_ST26000NM000C-... \
    /dev/disk/by-id/scsi-SATA_ST26000NM000C-...

sudo mkdir -p /mnt/media/{movies,shows,audiobooks,downloads}
sudo chown -R root:plex-rw /mnt/media
sudo chmod -R 2775         /mnt/media
sudo setfacl -R    -m g:plex-ro:rx /mnt/media
sudo setfacl -R -d -m g:plex-ro:rx /mnt/media   # default ACL — new files inherit
```

### Build the personal pool (2-way mirror, 2× 8TB)

```bash
sudo zpool create -o ashift=12 \
  -O compression=lz4 \
  -O atime=off \
  -O xattr=sa \
  -O acltype=posixacl \
  -O mountpoint=/mnt/personal \
  personal mirror \
    /dev/disk/by-id/scsi-SATA_ST8000NM023B-... \
    /dev/disk/by-id/scsi-SATA_ST8000NM023B-...

sudo zfs create personal/photos
sudo zfs create personal/documents
sudo zfs create personal/backups

sudo chown -R root:personal-rw /mnt/personal
sudo chmod -R 2775             /mnt/personal
```

ZFS auto-imports pools on boot via the cache file written by `zpool create` — no fstab entry needed.

### Service users and groups

```bash
# Create service users
for u in plex immich minecraft qbittorrent audiobookshelf sonarr radarr; do
  sudo useradd -r -s /sbin/nologin "$u"
done

# Create groups
for g in plex-rw plex-ro personal-rw personal-ro; do
  sudo groupadd "$g"
done

# Assign groups
sudo usermod -aG plex-rw     qbittorrent sonarr radarr jason-server
sudo usermod -aG plex-ro     plex audiobookshelf
sudo usermod -aG personal-rw immich jason-server
```

</details>

### Copy photos to server

Once `/mnt/personal/photos` exists, copy photos from your main PC over SSH:

```bash
# Run on your main PC
rsync -av --progress "/media/jason/Removable Drive/Pictures/" jason-server@192.168.50.186:/mnt/personal/photos/
```

Run the IDs script to look up UIDs/GIDs and automatically patch the compose files:
```bash
scripts/setup/phase4-ids.sh
```

### Pool failure alerts and disk monitoring

```bash
source ~/workspace/home-server/.env
scripts/setup/phase4-alerts.sh
```

This wires up msmtp (Gmail relay), the ZFS Event Daemon (zed) for pool-degraded / scrub-failed emails, and a daily disk-usage check at 08:00 for `/mnt/media` and `/mnt/personal`.

### Memory tuning (ARC cap + swappiness)

```bash
sudo bash scripts/setup/phase4-tuning.sh
```

Caps ZFS ARC at 16 GB and lowers `vm.swappiness` to 10. Without this, ARC will balloon to ~50% of RAM (~24 GB on a 48 GB box) and won't release fast enough when something else reads a large file (e.g., loading a 65 GB GGUF from `/mnt/cache/huggingface`) — the kernel then evicts process pages to swap. 16 GB ARC is plenty for media-mostly workloads where Plex/torrents are network-bound, not cache-bound.

### Monthly scrubs

```bash
sudo systemctl enable --now zfs-scrub-monthly@media.timer
sudo systemctl enable --now zfs-scrub-monthly@personal.timer
```

To stagger scrubs (avoid contending on the HBA's PCIe x1 bandwidth), shift `personal` to the 15th:

```bash
sudo mkdir -p /etc/systemd/system/zfs-scrub-monthly@personal.timer.d/
sudo tee /etc/systemd/system/zfs-scrub-monthly@personal.timer.d/override.conf > /dev/null <<'EOF'
[Timer]
OnCalendar=
OnCalendar=*-*-15 03:00:00
EOF
sudo systemctl daemon-reload
sudo systemctl restart zfs-scrub-monthly@personal.timer
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

ROCm containers use device passthrough — no extra toolkit needed. The GPU is exposed via `/dev/kfd` (compute) and `/dev/dri` (video), which are passed in each service's `docker-compose.yml`.

</details>

Verify GPU is accessible from Docker:
```bash
docker run --rm --device=/dev/kfd --device=/dev/dri \
  --group-add video --group-add render \
  rocm/rocm-terminal rocm-smi
```

---

## Phase 6 — Nginx Proxy Manager

Router config and firewall were handled in Phase 1. This phase starts NPM and configures proxy hosts.

See [`networking/setup.md`](networking/setup.md) — Phase 6 section for full details.

---

## Phase 7 — Tailscale

Mesh VPN for remote access to LAN-only admin UIs and ad-blocking on the go.

See [`networking/setup.md`](networking/setup.md) — Phase 7 section.

---

## Phase 8 — Services (Docker Compose)

Start services in this order — see each directory's `setup.md` for details:

1. [`plex/setup.md`](plex/setup.md)
2. [`minecraft/setup.md`](minecraft/setup.md)
3. [`photos/setup.md`](photos/setup.md)
4. [`torrent/setup.md`](torrent/setup.md)
5. [`llm/setup.md`](llm/setup.md)
6. [`audiobooks/setup.md`](audiobooks/setup.md)
7. [`monitoring/setup.md`](monitoring/setup.md)
8. [`passwords/setup.md`](passwords/setup.md)
9. [`adblock/setup.md`](adblock/setup.md)
10. [`notes/setup.md`](notes/setup.md)
11. [`api/setup.md`](api/setup.md)
12. [`audio/setup.md`](audio/setup.md)
13. [`backups/setup.md`](backups/setup.md) — wire up local + offsite backups before going to production
14. [`updater/setup.md`](updater/setup.md) — start this last
