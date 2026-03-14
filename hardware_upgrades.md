# Hardware Upgrade Plan

## Phase 1 — AM4 Platform Swap

Replace the Sandy Bridge platform with AM4 hardware already owned.

### Hardware in hand
| Component | Details |
|-----------|---------|
| Motherboard | MSI B350 Tomahawk |
| RAM | 16GB DDR4 |
| CPU Cooler | Stock AMD Wraith (from main PC build) |

### CPU strategy
The B350 Tomahawk supports Ryzen 5000 (Vermeer) via beta BIOS, but has no BIOS flashback — an older AM4 CPU is required to boot and flash first.

**Step 1 — Get a cheap 3000-series CPU (~$30-50 on eBay)**
Any Matisse or Picasso chip works. Just needs to POST so the BIOS can be flashed to "Latest Beta BIOS" from the MSI support page.

**Step 2 — Flash to latest beta BIOS**
This unlocks Ryzen 5000 support and future-proofs the board.

**Step 3 — Drop in 5000-series when it cascades from main PC**
When the main PC gets a new platform, the current CPU moves to the server. Good 65W targets:
- Ryzen 7 5700X — 8c/16t, 65W ⭐ preferred
- Ryzen 5 5600X — 6c/12t, 65W

Avoid 105W chips (5800X, 5900X, 5950X) for 24/7 server use — B350 VRM wasn't designed for sustained load at that TDP.

### Migration notes
- Linux and Docker configs carry over seamlessly
- RAID array reassembles automatically
- Reinstall NVIDIA drivers after platform swap
- Note new CPU/RAM specs in `hardware.md` after swap
