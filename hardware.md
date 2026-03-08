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

> **TODO:** Fill in what you have

| Component | Have | Notes |
|-----------|------|-------|
| CPU | | |
| Motherboard | | |
| RAM | | |
| OS Drive | | |
| Media Drive(s) | | |
| GPU / iGPU | | |
| Case | | |
| PSU | | |
| Network | | |

---

## Still Needed

> **TODO:** To be determined after hardware audit above

---

## Notes

- Linux Mint will be installed on the OS drive
- Media drives mount at `/mnt/<drive-name>/`
- A wired connection to the router is strongly preferred over Wi-Fi for Plex and Minecraft
