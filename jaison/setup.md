# jaison — Setup

Mirrors the media box's `setup.md` phases; ZFS, NPM, Tailscale and the
service stacks don't apply here. Everything after Phase 1 runs over SSH.

## Phase 1 — OS Install (Ubuntu Server 26.04.1 LTS)

1. Boot from the USB (F8 on the ASUS POST screen for the boot menu). Board
   defaults are fine; enable the RAM's EXPO/XMP profile in the BIOS so the
   DDR5-5600 kit runs at 5600 rather than the 5200 JEDEC default.
2. Install Ubuntu Server: target the 1 TB NVMe, use the entire disk, **untick
   "set up this disk as an LVM group"** (a single ext4 root; nothing here needs
   LVM), enable SSH, user `jason`.
3. Remove the USB, boot, then from your PC:
   ```bash
   ssh-copy-id jason@<ip>
   ```

### Network

- Router: DHCP reservation for this box's MAC (wired port; the 10GbE/2.5GbE
  ports on the SAGE A, not Wi-Fi). Same subnet as the media box.
- AdGuard (on the media box): DNS rewrite `jaison` → that IP, so nothing has to
  carry the address.
- Verify from the media box: `ping jaison`.

### Update, firewall, reboot

```bash
sudo apt update && sudo apt upgrade -y
scripts/phase1-firewall.sh      # 22 from the LAN, 11436 from the media box only
# the wired 10GbE/2.5GbE ports have no link until they're cabled; don't let boot wait on them
sudo systemctl mask systemd-networkd-wait-online.service
sudo reboot
```

Wi-Fi is configured by the installer (netplan + wpa_supplicant). If the installer
crashes on its network screen with `NetlinkDumpInterrupted`, that's the Wi-Fi scan
racing; just retry the installer, it's timing-dependent.

## Phase 2 — GitHub

The repo is public, so cloning needs no key; pushing from this box does.

```bash
git clone https://github.com/fagerbergj/home-server.git ~/workspace/home-server
ssh-keygen -t ed25519 -C "jaison"
cat ~/.ssh/id_ed25519.pub   # add to GitHub if this box should push; then switch the remote to git@github.com:fagerbergj/home-server.git
```

The `llm/` stack reads `LLM_API_KEY` and `HF_TOKEN` from the environment;
copy the two lines from the media box's root `.env` into `~/workspace/home-server/.env`
here (export-style, `set -a && . .env` before compose).

## Phase 3 — AMD GPUs

```bash
scripts/phase3-gpu.sh
sudo reboot
```

The in-tree `amdgpu` driver handles RDNA 4; the script adds the ROCm userspace
(`rocm-smi` for monitoring), the render/video groups, and a udev rule that
**disables GPU runtime power management**. Without that rule an idle card
suspends, every 30 s poll from an exporter wakes it, and one failed resume
hung the media box hard on 2026-08-29.

Verify after the reboot:

```bash
rocm-smi                                   # both R9700s, VK order is reversed vs this
cat /sys/bus/pci/devices/*/power/control   # the two GPU entries must say "on"
```

## Phase 4 — Memory and storage

```bash
scripts/phase4-tuning.sh    # swappiness 10; no ZFS here, so no ARC cap
sudo mkdir -p /mnt/cache/huggingface && sudo chown $USER: /mnt/cache /mnt/cache/huggingface
```

`/mnt/cache` is a plain directory on the NVMe root (kept at the same path as the
media box so `llm/` compose and `download-models.sh` work unchanged).

## Phase 5 — Docker

```bash
scripts/phase5-docker.sh
```

Plain Docker; the Vulkan llama.cpp image needs only `/dev/dri` + `/dev/kfd`
passthrough, which `llm/docker-compose.yml` already declares.

## Phase 6 — Models

Pull the working set from the media box's archive (wired; ~275 GB):

```bash
scripts/phase6-models.sh    # rsync from jason-server:/mnt/media/models/huggingface
```

Or re-download: `llm/download-models.sh`.

## Phase 7 — llm-swap

```bash
cd ~/workspace/home-server/llm
set -a && . ../.env && set +a
make swap-up
curl -s http://localhost:11436/v1/models | jq '.data[].id'
```

Check card placement matches `llm-swap.yaml`'s `GGML_VK_VISIBLE_DEVICES` pins
(`vulkaninfo --summary` device order vs `rocm-smi`; they're reversed).

## Phase 8 — Wire the media box

On `jason-server`:

1. Traefik file-provider route for `/openai` → `http://jaison:11436` (see
   `api/traefik/dynamic/`), keeping the `llm-apikey` + `llm-strip` middlewares.
2. `quack/docker-compose.yml`: `QUACK_LLM_ENDPOINT=http://jaison:11436/v1`,
   then `docker compose up -d quack`.
3. Optional: run a `server-cuda` llama-swap on the 3090 for `qwen3-embed` and
   add it as a `peers:` entry in this box's `llm-swap.yaml`.
4. Smoke test: `/review` on a PR and watch `docker logs quack`.
