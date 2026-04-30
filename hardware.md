# Hardware

## Current Hardware

| Component | Status | Notes |
|-----------|--------|-------|
| CPU | AMD Ryzen 5 5500 (Cezanne, 6c/12t, 3.6GHz, 65W) | ✅ |
| Motherboard | GIGABYTE B550 Eagle WIFI6 (AM4, B550 chipset) | ✅ Native Ryzen 5000 support, PCIe 4.0, WIFI6 |
| RAM | 32GB DDR4 | ✅ Upgraded from 16GB |
| CPU Cooler | Stock AMD Wraith | ✅ |
| OS Drive | 500GB NVMe (M.2) | ✅ |
| HBA | LSI 9300-16i (SAS3008, IT mode) | ✅ Single controller for all 6 HDDs; PCIEX1_4 slot, negotiates PCIe 3.0 x1 (~985 MB/s) |
| Media Pool | 4× 26TB Seagate Exos `ST26000NM000C` (mfr-recert, 5yr warranty) | ✅ ZFS RAIDZ2, ~46 TiB usable |
| Personal Pool | 2× 8TB Dell `J7W80` (Seagate Exos rebadge, new) | ✅ ZFS 2-way mirror, ~7.3 TiB usable; 2 bays free for future expansion |
| GPU | RTX 3090 (Ampere, 24GB VRAM) | ✅ 24GB VRAM for LLM inference, excellent NVENC |
| PSU | 1200W | ✅ |
| Network | Intel GbE LAN (onboard, `enp6s0`) + WIFI6 | ✅ Gigabit |
| Case | Fractal Design Define R5 (ATX Mid Tower, 8× 3.5" bays) | ✅ 6 bays in use, 2 free |

---

## Drive Layout

| Mount Point | Pool | Layout | Drives | Owner | Group | Access |
|-------------|------|--------|--------|-------|-------|--------|
| `/` | — | — | 500GB NVMe (M.2) — Ubuntu Server 24.04 LTS + Docker configs | — | — | — |
| `/mnt/media` | `media` | RAIDZ2 | 4× 26TB Seagate Exos | `root` | `plex-rw` | `jason` (rw), `qbittorrent`/`sonarr`/`radarr` (rw), `plex`/`audiobookshelf` (ro) |
| `/mnt/personal` | `personal` | 2-way mirror | 2× 8TB Dell J7W80 | `root` | `personal-rw` | `jason` (rw), `immich` (rw) |

`/mnt/media` is a flat layout with `movies/`, `shows/`, `audiobooks/`, and `downloads/` subdirectories — replaces the legacy `/mnt/plex01` + `/mnt/plex02` split that existed only because the old setup had two separate ext4 drives.

`/mnt/personal` has datasets `personal/photos`, `personal/documents`, and `personal/backups` so each can be snapshotted/quota'd independently.

---

## Platform Notes

- AM4 / B550 Eagle WIFI6 — Ryzen 5 5500, native Ryzen 5000 support (no BIOS flash workaround needed).
- All four chipset PCIEX1 slots on this board are wired x1 electrical despite being x16 physical, so the HBA negotiates PCIe 3.0 x1. Slot choice is driven by cooling (above the bottom intake fan), not bandwidth. See `hardware_upgrades.md` for the full slot/bandwidth analysis.
- HBA temperature: SAS3008 die runs 70–85 °C under load; throttle threshold is 95 °C. Monitor with `sensors | grep -A2 mpt3sas`.
