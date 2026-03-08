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
| RAM | 4GB DDR3 PC3-10600 (1333MHz) | ❌ Not enough — needs upgrade |
| OS Drive | 640GB Hitachi HDD (SATA 3Gbps) | ❌ No SSD — will feel slow; too small long-term |
| Media Drive(s) | (same 640GB HDD, shared) | ❌ Needs dedicated media storage |
| GPU | EVGA GTX 780 (Kepler, 3GB VRAM) | ✅ Supports NVENC hardware transcoding (Plex Pass required) |
| iGPU | Intel HD Graphics 3000 (in CPU) | ⚠️ Quick Sync gen 1 — usable but NVENC from GTX 780 is better |
| PSU | EVGA 500W AXI | ✅ Sufficient for this build |
| Network | Realtek Gigabit LAN (onboard) | ✅ Gigabit — good |
| Case | None yet | ❌ Needed — see case recommendation below |

---

## Assessment

### What's fine
- **PSU** — 500W is plenty
- **Network** — onboard Gigabit is good, just make sure it's wired to the router
- **GPU** — GTX 780 NVENC can handle Plex hardware transcoding, removing most CPU load
- **CPU** — i7-2700K is old (2011) but has 4 cores/8 threads; paired with NVENC it can run Plex + Minecraft simultaneously

### What's a problem
- **RAM (4GB)** — this is the biggest bottleneck. OS + Plex + Minecraft + Immich will easily exceed 4GB. The board has 2 DIMM slots and supports up to **16GB DDR3**. DDR3 is cheap now.
- **No SSD** — running Linux Mint and Docker off a spinning HDD will be noticeably slow, especially on boot and during Docker operations. A SATA SSD is inexpensive.
- **Storage** — 640GB shared between OS and media is not enough once a real library builds up. Needs at least one dedicated media drive.

### Platform age note
The LGA1155 / Sandy Bridge platform is from 2011 and is end-of-life. It will work fine as a home server, but there's no upgrade path beyond what DDR3 and this socket support. Plan to eventually replace the whole platform if needs grow significantly.

---

## Still Needed

| Item | Priority | Notes |
|------|----------|-------|
| SSD (SATA, 120–256GB) | **High** | OS + Docker config drive |
| RAM upgrade (2×8GB DDR3 1600) | **High** | Bring total to 16GB — max for this board |
| Media HDD (2–4TB+) | **High** | Dedicated drive for Plex + photos |
| Second media HDD (optional) | Medium | If library is large, separate Plex/photos drives |
| NVIDIA drivers + nvidia-container-toolkit | **High** | Required for GTX 780 NVENC in Docker |
| ATX mid-tower case | **High** | See case notes below |
| CPU cooler (LGA1155) | Medium | Stock cooler is loud/hot for 24/7 use — Cooler Master Hyper 212 recommended (~$30 new, less used) |

---

## Case

**Recommendation: Full ATX mid-tower**

Reasoning:
- Floor placement behind desk — size/aesthetics don't matter
- mATX board fits in any ATX case, no constraint
- Need 4+ HDD bays for expansion (starting with 2×2TB, will grow)
- Full-size GPU now and when upgrading later
- Better airflow for GTX 780 which runs hot

**Suggested:** Fractal Design Define 7 or Define R6
- Modular HDD trays (up to 9 drives configurable)
- Very quiet with noise dampening
- Great airflow and cable management
- New ~$120, used ~$60–80

**PSU note:** 500W is fine for current hardware but when you drop a modern GPU in later, you'll likely need to upgrade the PSU at the same time. Budget for that when the time comes.

---

## Notes

- Linux Mint will be installed on the OS drive
- Media drives mount at `/mnt/<drive-name>/`
- A wired connection to the router is strongly preferred over Wi-Fi for Plex and Minecraft
