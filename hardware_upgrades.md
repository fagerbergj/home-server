# Hardware Upgrade Plan

## Phase 1 — AM4 Platform Swap

Replace the Sandy Bridge platform with AM4 hardware already owned.

### Hardware in hand
| Component | Details |
|-----------|---------|
| Motherboard | MSI B350 Tomahawk |
| RAM | 32GB DDR4 | ✅ Upgraded from 16GB |
| CPU Cooler | Stock AMD Wraith (unused, stored in CPU box) |

### CPU strategy
The B350 Tomahawk supports Ryzen 5000 (Vermeer) via beta BIOS, but has no BIOS flashback — an older AM4 CPU is required to boot and flash first.

**~~Step 1 — Get a cheap 3000-series CPU~~** ✅ Ryzen 5 3600 installed
**~~Step 2 — Flash to latest beta BIOS~~** ✅ Done — Ryzen 5000 support unlocked

**Step 3 — Drop in 5000-series when it cascades from main PC**
When the main PC gets a new platform, the current CPU moves to the server. Good 65W targets:
- Ryzen 7 5700X — 8c/16t, 65W ⭐ preferred
- Ryzen 5 5600X — 6c/12t, 65W

Avoid 105W chips (5800X, 5900X, 5950X) for 24/7 server use — B350 VRM wasn't designed for sustained load at that TDP.

### Migration notes
- Linux and Docker configs carry over seamlessly
- Update netplan interface name (was `enp4s0`, now `enp35s0` on B350 Tomahawk)
- RAID array reassembles automatically
- Reinstall NVIDIA drivers after platform swap
- Note new CPU/RAM specs in `hardware.md` after swap

---

## Phase 2 — OS Drive Replacement

**Priority:** Low — drive is passing SMART tests and wear is minimal, but worth planning.

The ADATA SU650 480GB (sda) has been running for **4.25 years** (37,304 power-on hours) and has 11 reallocated + 11 pending sectors. Extended SMART test passed clean and remaining lifetime shows 100%, so it's not urgent — but the pending sectors are worth monitoring.

**Watch for:** `Current_Pending_Sector` count climbing above 11. If it grows, replace promptly.

**Replacement target:** Any 500GB–1TB SATA SSD. Nothing special needed — OS + Docker, no heavy write load.

**Migration:** Reinstall Ubuntu Server 24.04 and re-run setup from `setup.md`. All service configs are in Git; the only manual step is restoring `.env`.

---

## Phase 3 — GPU Upgrade ✅ Complete

Installed **RTX 3090 24GB** (replacing 2x GTX 1070). Also upgraded PSU to 1200W to support the higher TDP.

- 24GB VRAM comfortably runs 30B+ quantized models
- Ampere NVENC is a significant step up for Plex transcoding
- See `llm/README.md` for updated model guidance
