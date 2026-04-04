# Hardware

## Current Hardware

| Component | Status | Notes |
|-----------|--------|-------|
| CPU | AMD Ryzen 5 5500 (Cezanne, 6c/12t, 3.6GHz, 65W) | ✅ |
| Motherboard | GIGABYTE B550 Eagle WIFI6 (AM4, B550 chipset) | ✅ Native Ryzen 5000 support, PCIe 4.0, WIFI6 |
| RAM | 32GB DDR4 | ✅ Upgraded from 16GB |
| CPU Cooler | Stock AMD Wraith | ✅ |
| OS Drive | 480GB ADATA SU650 SSD | ✅ |
| Personal Drive (primary) | 1TB Seagate HDD | ✅ RAID 1 primary |
| Personal Drive (secondary) | 1TB WD HDD | ✅ RAID 1 secondary — 35,648 hrs, healthy SMART |
| Plex Drive | 4TB Seagate Barracuda HDD | ✅ |
| Plex Drive (overflow) | 640GB Hitachi Deskstar HDD | ⚠️ Old drive (41k hrs) — non-critical re-downloadable media only |
| GPU | RTX 3090 (Ampere, 24GB VRAM) | ✅ 24GB VRAM for LLM inference, excellent NVENC |
| PSU | 1200W | ✅ Upgraded from 500W |
| Network | Intel GbE LAN (onboard, `enp6s0`) + WIFI6 | ✅ Gigabit |
| Case | Fractal Design Define R5 (ATX Mid Tower) | ✅ |

---

## Drive Layout

| Mount Point | Drive | Purpose | Owner | Group | Access |
|-------------|-------|---------|-------|-------|--------|
| `/` | 480GB ADATA SU650 SSD | Ubuntu Server 24.04 LTS + Docker configs | — | — | — |
| `/mnt/plex01` | 4TB Seagate Barracuda | Plex movies & shows | `root` | `plex-rw` | `jason` (rw), `qbittorrent` (rw), `plex` (ro) |
| `/mnt/personal01` | RAID 1 (1TB Seagate + 1TB WD) | Immich photos & personal videos | `root` | `personal-rw` | `jason` (rw), `immich` (rw) |
| `/mnt/plex02` | 640GB Hitachi Deskstar HDD | Plex overflow — re-downloadable media only | `root` | `plex-rw` | `jason` (rw), `qbittorrent` (rw), `plex` (ro) |

---

## Platform Notes

- AM4 / B550 Eagle WIFI6 — Ryzen 5 5500, native Ryzen 5000 support (no BIOS flash workaround needed)
