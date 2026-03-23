# Hardware

## Current Hardware

| Component | Status | Notes |
|-----------|--------|-------|
| CPU | AMD Ryzen 5 3600 (Matisse, 6c/12t, 3.6GHz, 65W) | ⚠️ Interim — 5000-series replaces this when it cascades from main PC |
| Motherboard | MSI B350 Tomahawk (AM4, B350 chipset) | ✅ Flashed to latest beta BIOS (Ryzen 5000 ready) |
| RAM | 32GB DDR4 | ✅ Upgraded from 16GB |
| CPU Cooler | Stock AMD Wraith | ✅ |
| OS Drive | 480GB ADATA SU650 SSD | ✅ |
| Personal Drive (primary) | 1TB Seagate HDD | ✅ RAID 1 primary |
| Personal Drive (secondary) | 1TB WD HDD | ✅ RAID 1 secondary — 35,648 hrs, healthy SMART |
| Plex Drive | 4TB Seagate Barracuda HDD | ✅ |
| Plex Drive (overflow) | 640GB Hitachi Deskstar HDD | ⚠️ Old drive (41k hrs) — non-critical re-downloadable media only |
| GPU | 2x GTX 1070 Ti (Pascal, 8GB VRAM each) | ✅ Excellent NVENC, ~180W each — no NVLink, Ollama splits layers across both GPUs (~16GB effective for inference) |
| PSU | EVGA 500W AXI | ✅ Sufficient |
| Network | Realtek Gigabit LAN (onboard, `enp35s0`) | ✅ Gigabit |
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

- AM4 / B350 Tomahawk — Ryzen 5 3600 interim, awaiting 5000-series cascade from main PC
- See [`hardware_upgrades.md`](hardware_upgrades.md) for next steps
