# Hardware Evaluation

## Service Requirements

### Plex Media Server
- **CPU:** Modern quad-core minimum; iGPU (Intel Quick Sync) strongly recommended for hardware transcoding
- **RAM:** 4 GB minimum, 8 GB recommended
- **Storage (OS/config):** 60 GB SSD minimum
- **Network:** Wired Gigabit Ethernet recommended

### Minecraft Server (Java Edition)
- **CPU:** Single-thread performance matters more than core count; modern CPU recommended
- **RAM:** 2–4 GB dedicated to the JVM (on top of OS + Plex needs)
- **Storage:** Minimal — world files grow over time but start small (~500 MB)

### Photo Storage (Immich recommended)
- **CPU:** Light under normal use; CPU spikes during photo indexing/ML face detection
- **RAM:** 2–4 GB (ML worker is memory-hungry during initial indexing)
- **Storage:** Depends entirely on photo library size — plan for a dedicated drive or partition

---

## Combined Minimums

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | Quad-core, 8th gen Intel+ | i5/i7 with iGPU (Quick Sync) |
| RAM | 8 GB | 16 GB |
| OS Drive | 120 GB SSD | 256 GB SSD |
| Media/Photo Drive(s) | Depends on library | 2–4 TB HDD per drive |
| Network | 100 Mbps wired | Gigabit wired |

---

## Current Hardware

| Component | Have | Assessment |
|-----------|------|------------|
| CPU | Intel Core i7-2700K (Sandy Bridge, 4c/8t, 3.5GHz) | ⚠️ Old but functional — see notes |
| Motherboard | ASUS P8H61-M LE/CSM (LGA1155, H61 chipset) | ⚠️ Old platform, max 16GB DDR3, 2 DIMM slots |
| RAM | 16GB (2×8GB) Silicon Power DDR3-1600 CL11 | ✅ Purchased — maxes out the board |
| OS Drive | 256GB ADATA SSD (moving from main PC) | ✅ Good — Linux Mint + Docker config |
| Media Drive 1 | 1TB HDD (moving from main PC) | ✅ Secondary media / overflow |
| Media Drive 2 | 4TB Seagate Barracuda HDD | ✅ Purchased — primary media drive |
| GPU | GTX 1070 Ti (Pascal, 8GB VRAM) | ✅ Excellent NVENC — handles multiple simultaneous transcode streams |
| iGPU | Intel HD Graphics 3000 (in CPU) | ⚠️ Quick Sync gen 1 — superseded by 1070 Ti NVENC |
| PSU | EVGA 500W AXI | ✅ Sufficient for this build |
| Network | Realtek Gigabit LAN (onboard) | ✅ Gigabit — good |
| Case | Fractal Design Define R5 (ATX Mid Tower) | ✅ Purchased |

---

## Assessment

### What's good
- **RAM** — 16GB maxes out the board, plenty for Plex + Minecraft + Immich
- **Storage** — 256GB SSD for OS, 1TB + 4TB for media gives solid capacity to start
- **PSU** — 500W is sufficient for current hardware
- **Network** — onboard Gigabit, just keep it wired to the router
- **GPU** — GTX 1070 Ti Pascal NVENC is excellent, handles multiple simultaneous transcode streams, lower power draw than 780 (~180W vs 250W)
- **Case** — Define R5 has plenty of HDD bays for future expansion

### Remaining concerns
- **CPU** — i7-2700K is old (2011, Sandy Bridge) but functional with NVENC offloading transcoding
- **CPU cooler** — stock cooler is loud and marginal for 24/7 use; see below
- **PSU future note** — 500W is fine now, but budget for an upgrade when dropping in a modern GPU later

### Platform age note
LGA1155 / Sandy Bridge is end-of-life (2011). Works fine as a home server for now. Plan to replace the whole platform (CPU, mobo, RAM) when needs outgrow it — likely when upgrading the main PC and cascading parts.

---

## Still Needed

| Item | Priority | Notes |
|------|----------|-------|
| CPU cooler (LGA1155) | Medium | Stock cooler loud/hot for 24/7 — Cooler Master Hyper 212 (~$30 new) |
| NVIDIA drivers + nvidia-container-toolkit | High | Required for GTX 780 NVENC in Docker — software, not hardware |

---

## Drive Layout

| Mount Point | Drive | Purpose | Service User |
|-------------|-------|---------|--------------|
| `/` (OS) | 256GB ADATA SSD | Linux Mint + Docker configs | — |
| `/mnt/plex01` | 4TB Seagate Barracuda | Plex movies & TV | `plex` |
| `/mnt/personal01` | 1TB HDD | Immich photos & personal videos | `immich` |

---

## Notes

- OS: Linux Mint
- All services run via Docker Compose
- Media drives mount at `/mnt/<drive-name>/`
- Wired connection to router strongly preferred over Wi-Fi
- **PSU note:** 500W is fine for current hardware but when dropping in a modern GPU later, upgrade PSU at the same time
