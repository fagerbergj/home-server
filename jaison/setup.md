# jaison — Setup

Mirrors the media box's `setup.md` phases; ZFS, NPM, Tailscale and the service stacks don't apply here. Everything after Phase 1 runs over SSH.

## Phase 1 — OS Install (Ubuntu Server 26.04.1 LTS)

1. Boot from the USB (F8 on the ASUS POST screen for the boot menu). Board defaults are fine; enable the RAM's EXPO/XMP profile in the BIOS so the DDR5-5600 kit runs at 5600 rather than the 5200 JEDEC default.
2. Install Ubuntu Server: target the 1 TB NVMe, use the entire disk, enable SSH, user `jason`. If you leave the LVM default on, the installer caps the root LV at 100 GB; afterwards `sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv && sudo resize2fs /dev/ubuntu-vg/ubuntu-lv`.
3. Remove the USB, boot, then from your PC:
   ```bash
   ssh-copy-id jason@<ip>
   ```

### Network

- Router: DHCP reservation for this box's MAC at `192.168.50.202` (currently the Wi-Fi interface `wlp145s0`; if it moves to a wired port, reserve that MAC instead).
- AdGuard Home (media box UI): **Filters → DNS rewrites → Add**: `jaison` → `192.168.50.202`, and `jason-server` → `192.168.50.186`. Every config that crosses the boxes (Traefik route, `QUACK_LLM_ENDPOINT`, llama-swap `peers`) uses those names, so an address change is one rewrite, not three files. Only clients that use AdGuard as DNS see them; containers on the media box resolve through the host, so the host's resolver must point at AdGuard (check `resolvectl status` there) or those configs need the IP.
- Verify: `ping jaison` from the media box, `ping jason-server` from here.
- Tailscale (optional, for SSH from off-LAN): `curl -fsSL https://tailscale.com/install.sh | sh`, `sudo tailscale up --ssh`, `sudo ufw allow in on tailscale0`. Not an exit node or subnet router; the media box already is.

### Update, firewall, reboot

```bash
sudo apt update && sudo apt upgrade -y
scripts/phase1-firewall.sh      # 22 from the LAN, 11436 from the media box only
# the wired 10GbE/2.5GbE ports have no link until they're cabled; don't let boot wait on them
sudo systemctl mask systemd-networkd-wait-online.service
sudo reboot
```

Wi-Fi is configured by the installer (netplan + wpa_supplicant). If the installer crashes on its network screen with `NetlinkDumpInterrupted`, that's the Wi-Fi scan racing; just retry the installer, it's timing-dependent. Pick the **5 GHz** SSID: the 2.4 GHz one links at ~230 Mbit (7-10 MB/s real), the 5 GHz one at 160 MHz / ~1.9 Gbit (~85 MB/s real). To switch after the fact: `sudo sed -i 's/<2GHz SSID>:/<5GHz SSID>:/' /etc/netplan/*.yaml && sudo netplan apply`, then `iw dev wlp145s0 link` (`sudo apt install iw`) shows `freq: 5xxx`.

## Phase 2 — GitHub

The repo is public, so cloning needs no key; pushing from this box does.

```bash
git clone https://github.com/fagerbergj/home-server.git ~/workspace/home-server
ssh-keygen -t ed25519 -C "jaison"
cat ~/.ssh/id_ed25519.pub   # add to GitHub if this box should push; then switch the remote to git@github.com:fagerbergj/home-server.git
```

The `llm/` stack reads `LLM_API_KEY` and `HF_TOKEN` from the environment; copy the two lines from the media box's root `.env` into `~/workspace/home-server/.env` here (export-style, `set -a && . .env` before compose).

## Phase 3 — AMD GPUs

```bash
scripts/phase3-gpu.sh
sudo reboot
```

The in-tree `amdgpu` driver handles RDNA 4; the script adds the ROCm userspace (`rocm-smi` for monitoring), the render/video groups, and a udev rule that **disables GPU runtime power management**. Without that rule an idle card suspends, every 30 s poll from an exporter wakes it, and one failed resume hung the media box hard on 2026-08-29.

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

`/mnt/cache` is a plain directory on the NVMe root (kept at the same path as the media box so `llm/` compose and `download-models.sh` work unchanged).

## Phase 5 — Docker

```bash
scripts/phase5-docker.sh
```

Plain Docker; the Vulkan llama.cpp image needs only `/dev/dri` + `/dev/kfd` passthrough, which `llm/docker-compose.yml` already declares.

## Phase 6 — Models

Pull the working set from the media box's archive (wired; ~275 GB):

```bash
scripts/phase6-models.sh    # rsync from jason-server:/mnt/media/models/huggingface
```

Or re-download: `llm/download-models.sh`.

## Phase 7 — llm-swap

One `llm-swap` container (llama-swap + Docker CLI, host networking, `/var/run/docker.sock`). Every model in `llm-swap.yaml` is a `docker run` of its runtime image, stopped with `cmdStop: docker stop`, so one router owns both cards and its groups swap the resident 27B (vLLM, TP=2, one id for worker and judge) against Flash-Next (whole box, llama.cpp MTP fork from `jaison/llm/mtp`) and on-demand extras (Vulkan llama.cpp). Bind-mount paths in cmds are host paths; `jaison/llm` is mounted at its host path for the vLLM launcher, which bind-mounts `jaison/llm/vllm-patches/` over the image.

vLLM checkpoints live in `/mnt/cache/vllm/` (`qwen3.8-27b-autoround`, `qwen3.8-27b-dflash2-int4`, `cache/` for the compile cache).

```bash
cd jaison/llm && set -a && . ../../.env && set +a
make up          # pulls runtime images, builds llama-mtp:gfx1201, starts the router
curl -s http://localhost:11436/v1/models | jq '.data[].id'
docker ps             # runtimes appear as qwen38-27b-vllm / flash-next / omni / muse while loaded
```

The 27B uses both cards (GPU=0,1, HIP order); Flash-Next's `-ts` leans on card 0 because `-ncmoe` offloads the first N layers.

## Phase 8 — Monitoring

```bash
cd ~/workspace/home-server/jaison && docker compose up -d   # node-exporter, amd-exporter, cadvisor
```

The media box's Prometheus scrapes them (`monitoring/prometheus/config.yaml`, jobs `jaison_*`) and Grafana shows the `jaison (AI box)` dashboard (`monitoring/grafana-dashboards/jaison.json`). The exporter ports are opened to the media box by `scripts/phase1-firewall.sh`.

## Phase 9 — Wire the media box

Configs use the reserved IP `192.168.50.202` rather than the AdGuard name: the media box's host resolver (and therefore Docker's embedded DNS) points at 1.1.1.1, not AdGuard, so LAN names don't resolve inside containers there.

The media box keeps its own llama-swap (`llm-swap-media`, CUDA image on the 3090, network alias `llm-swap`): it serves `qwen3-embed` and `qwen3.5-9b` locally and forwards every other model name to this box through its `peers:` block (`llm/llm-swap-media.yaml`, proxy `http://192.168.50.202:11436`). quack, Open WebUI and Traefik's `/openai` route all talk to that local endpoint, so this box being down only takes the big models with it. Keep the peer's model list in sync with `llm-swap.yaml` here.

On `jason-server` (`set -a && . .env && set +a` first for the LLM key):

1. `llm/`: `make media-up` (builds `llm-swap-cuda.Dockerfile`, starts llm-swap-media + qdrant + open-webui).
2. `api/`: `docker compose up -d traefik` (the file route `api/traefik/dynamic/llm.yml` reads `LLM_API_KEY` from the container env).
3. `quack/`: `docker compose up -d quack`.
4. Smoke test: `curl http://localhost:11436/v1/models` on the media box lists local + peer models; then `/review` on a PR and watch `docker logs quack`.
