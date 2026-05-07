# Hardware

## Current Hardware

| Component | Status | Notes |
|-----------|--------|-------|
| CPU | AMD Ryzen Threadripper 1950X (Whitehaven, 16c/32t, 3.4GHz base / 4.0GHz XFR, 180W) | ✅ 64 PCIe 3.0 lanes — chosen for the lane budget over per-core perf |
| Motherboard | ASUS ROG Strix X399-E Gaming (X399, sTR4) | ✅ 3× PCIe 3.0 x16 slots from CPU lanes; sensors via `asus_wmi_sensors` |
| RAM | 64GB DDR4-3000 (8× 8GB, true symmetric quad-channel, 1.35 V) | ✅ Matched pair per channel: 2× Crucial Ballistix 3000 CL16 + 2× Corsair LPX 3200 CL16 + 2× Corsair LPX 3000 CL15 + 2× Crucial Ballistix 3000 CL15 |
| CPU Cooler | DeepCool LT720 360mm AIO (sTR4 mount) | ✅ |
| OS Drive | 500GB NVMe (M.2) | ✅ Ubuntu + Docker images/overlay2; bind-mount service configs |
| Cache Drive | 480GB ADATA SU650 SATA SSD | ✅ Repurposed ex-OS drive at `/mnt/cache` — Ollama model store + scratch tier |
| HBA | LSI 9300-16i (SAS3008, IT mode) | ✅ Single controller for all 6 HDDs; runs at PCIe 3.0 x8 on Threadripper (~7.9 GB/s ceiling, far above what the drives can produce) |
| Media Pool | 4× 26TB Seagate Exos `ST26000NM000C` (mfr-recert, 5yr warranty) | ✅ ZFS RAIDZ2, ~46 TiB usable |
| Personal Pool | 2× 8TB Dell `J7W80` (Seagate Exos rebadge, new) | ✅ ZFS 2-way mirror, ~7.3 TiB usable; 2 bays free for future expansion |
| GPU | RTX 3090 (Ampere, 24GB VRAM) | ✅ 24GB VRAM for LLM inference, excellent NVENC; runs at full PCIe 3.0 x16 |
| PSU | 1200W | ✅ |
| Network | Intel GbE LAN (onboard) + WIFI6 | ✅ Gigabit |
| Case | Fractal Design Define 7 XL (E-ATX Full Tower) | ✅ 6× 3.5" in use; expandable to 18× 3.5" via multibracket kits |

---

## Drive Layout

| Mount Point | Pool / FS | Layout | Drives | Owner | Group | Access |
|-------------|-----------|--------|--------|-------|-------|--------|
| `/` | LVM ext4 | single | 500GB NVMe (M.2) — Ubuntu + Docker overlay2 + bind-mount configs | — | — | — |
| `/mnt/cache` | ext4 | single | 480GB ADATA SU650 SATA SSD — Ollama model store, scratch | `jason-server` | — | scratch tier; data is reproducible/disposable |
| `/mnt/media` | `media` (ZFS) | RAIDZ2 | 4× 26TB Seagate Exos | `root` | `plex-rw` | `jason` (rw), `qbittorrent`/`sonarr`/`radarr` (rw), `plex`/`audiobookshelf` (ro) |
| `/mnt/personal` | `personal` (ZFS) | 2-way mirror | 2× 8TB Dell J7W80 | `root` | `personal-rw` | `jason` (rw), `immich` (rw) |

`/mnt/media` is a flat layout with `movies/`, `shows/`, `audiobooks/`, and `downloads/` subdirectories — replaces the legacy `/mnt/plex01` + `/mnt/plex02` split that existed only because the old setup had two separate ext4 drives.

`/mnt/personal` has datasets `personal/photos`, `personal/documents`, and `personal/backups` so each can be snapshotted/quota'd independently.

`/mnt/cache` holds Ollama models (`/mnt/cache/ollama`) and a `scratch/` dir for reproducible large files. Single drive, no redundancy — only data that's cheap to regenerate (e.g., `ollama pull` re-downloads models). The drive is the original 480GB OS SSD, retained because surface-tested clean (badblocks pass) despite a stale SMART pending-sector count from a remap event the firmware never zeroed.

---

## Platform Notes

- **PCIe lanes**: Threadripper 1950X exposes 64 PCIe 3.0 lanes directly from the CPU. Both the GPU (x16) and the HBA (x8) get full electrical width without contending on a chipset uplink — the lane budget was the entire reason for picking this platform over the previous AM4/B550 build.
- **HBA bandwidth**: at PCIe 3.0 x8 the 9300-16i has ~7.9 GB/s of host-side bandwidth, so monthly scrubs across 6 drives in parallel and resilvers run unconstrained. This eliminates the ~50% scrub-time penalty the AM4/B550 build would have incurred at x1.
- **HBA temperature**: SAS3008 die runs 70–85 °C under load; throttle threshold is 95 °C. Monitor with `sensors | grep -A2 mpt3sas`.
- **Memory tuning**: ZFS ARC is capped at 16 GB and `vm.swappiness` is 10 (see `scripts/setup/phase4-tuning.sh`). Without the ARC cap, ZFS would consume ~50% of RAM and refuse to release for ext4 page cache when loading large mmap'd files (e.g., 24 GB Ollama models from `/mnt/cache`), pushing process pages to swap.
- **Note**: `hardware_upgrades.md` describes the original ZFS migration done on the AM4/B550 platform — its PCIe x1 analysis is no longer applicable here.
