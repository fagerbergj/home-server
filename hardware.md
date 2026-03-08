# Hardware

## Current Hardware

| Component | Status | Notes |
|-----------|--------|-------|
| CPU | Intel Core i7-2700K (Sandy Bridge, 4c/8t, 3.5GHz) | ⚠️ Old but functional — NVENC offloads transcoding |
| Motherboard | ASUS P8H61-M LE/CSM (LGA1155, H61 chipset) | ⚠️ Old platform, max 16GB DDR3, 2 DIMM slots |
| RAM | 16GB (2×8GB) Silicon Power DDR3-1600 CL11 | ✅ Purchased — maxes out the board |
| CPU Cooler | Stock Intel cooler | ⚠️ Marginal for 24/7 — upgrade eventually |
| OS Drive | 256GB ADATA SSD | ✅ Moving from main PC |
| Personal Drive (primary) | 1TB Seagate HDD | ✅ Purchased — RAID 1 primary |
| Personal Drive (secondary) | 1TB WD HDD | ✅ Moving from main PC — 35,648 hrs, healthy SMART |
| Plex Drive | 4TB Seagate Barracuda HDD | ✅ Purchased |
| GPU | GTX 1070 Ti (Pascal, 8GB VRAM) | ✅ From friend — excellent NVENC, ~180W |
| PSU | EVGA 500W AXI | ✅ Sufficient — upgrade when swapping to modern GPU |
| Network | Realtek Gigabit LAN (onboard) | ✅ Gigabit |
| Case | Fractal Design Define R5 (ATX Mid Tower) | ✅ Purchased |

---

## Drive Layout

| Mount Point | Drive | Purpose | Owner | Group |
|-------------|-------|---------|-------|-------|
| `/` | 256GB ADATA SSD | Linux Mint + Docker configs | — | — |
| `/mnt/plex01` | 4TB Seagate Barracuda | Plex movies & shows | `qbittorrent` | `plex-rw` / `plex-ro` |
| `/mnt/personal01` | RAID 1 (1TB Seagate + 1TB WD) | Immich photos & personal videos | `immich` | `personal-rw` |

---

## Platform Notes

- LGA1155 / Sandy Bridge (2011) — end-of-life but works fine for this use case
- Planned upgrade path: when upgrading main PC, cascade CPU/mobo/RAM to server
- On mobo swap: Linux and Docker configs carry over seamlessly; RAID array reassembles automatically; may need to reinstall NVIDIA drivers if GPU changes

---

## Still Needed

| Item | Priority | Notes |
|------|----------|-------|
| CPU cooler (LGA1155) | Low | Stock cooler is marginal for 24/7 — Hyper 212 (~$30) when ready |
