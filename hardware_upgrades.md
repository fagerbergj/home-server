# Hardware Upgrades

Running record of upgrades — both the history table (for context on why the build looks the way it does) and a detailed plan for the next upgrade in flight.

---

## Upgrade History

| Date | Upgrade | Why |
|------|---------|-----|
| 2026-03-08 | Platform: Sandy Bridge → MSI B350 Tomahawk + Ryzen 5 3600 (cascade from main PC).<br>Cooler: stock Intel → stock AMD Wraith.<br>GPU: GTX 1070 → 2× GTX 1070.<br>Drives: 4TB Seagate Barracuda (`plex01`), 2× 1TB (`personal01` mdadm RAID 1), 480GB ADATA SU650 SATA SSD (OS). | Modernize platform; B350 + Wraith already on hand. Add Plex media drive + redundant personal storage. Second GPU added for slightly better LLM split-layer inference. |
| 2026-03-14 | Added 640GB Hitachi Deskstar (`plex02`) as Plex overflow. | Old Hitachi was already on hand. |
| 2026-03-23 | RAM 16GB → 32GB DDR4. | More headroom for concurrent services and LLM models. |
| 2026-03-26 | GPU 2× GTX 1070 → RTX 3090 (24GB).<br>PSU 500W → 1200W. | Single GPU with 24GB unlocks larger LLMs (33B Q4 fits in VRAM); 3090 needs the wider power envelope. |
| 2026-04-04 | Motherboard MSI B350 Tomahawk → GIGABYTE B550 Eagle WIFI6.<br>CPU Ryzen 5 3600 → Ryzen 5 5500 (new purchase). | Accidentally broke the B350 Tomahawk during a GPU install, which killed the CPU with it. Replaced both with the B550 + a new Ryzen 5 5500. |
| 2026-04-16 | OS drive: 480GB ADATA SU650 → 500GB NVMe.<br>ADATA repurposed as `plex03` (additional Plex overflow). | ADATA SATA cable failure + 11 pending sectors; NVMe also gives 7×+ I/O for Docker overlay/image churn. |
| 2026-04-30 | **ZFS + Threadripper migration.**<br>Storage: mdadm RAID 1 + ext4 (`plex01`/`plex02`/`plex03`/`personal01`) → ZFS pools (`media` RAIDZ2 across 4× 26TB Seagate Exos, `personal` 2-way mirror across 2× 8TB Dell J7W80) on LSI 9300-16i HBA in IT mode.<br>Retired: 2× 1TB, 4TB Barracuda (DM-SMR — unsafe for ZFS), 640GB Hitachi (41k hrs).<br>Platform: B550 + Ryzen 5 5500 → ASUS ROG Strix X399-E + Threadripper 1950X.<br>RAM 32GB → 48GB DDR4 (mixed kits, see "Next upgrade").<br>Cooler: stock Wraith → DeepCool LT720 360mm AIO (sTR4 socket).<br>`plex03` (ADATA) repurposed as `/mnt/cache` for Ollama models + scratch. | ZFS for data integrity + capacity (~46 TiB usable) + scrubbing. Threadripper specifically for the 64 PCIe 3.0 lanes — B550 chipset slots are all wired x1 electrical, capping the HBA at ~985 MB/s and adding ~50% to scrub/resilver time. X399 puts the HBA on x8 (~7.9 GB/s, no contention). |

Each completed upgrade's full details and rationale live in the git history of this file (`git log -- hardware_upgrades.md`). Re-create as needed.

---

## Next upgrade: RAM 48 GB (mixed) → 64 GB (matched, ~2933 MT/s)

The current 6× 8GB layout populates all 4 channels but unevenly (16/8/16/8) and runs at 2400 MT/s because one of three mixed kits is rated 2400 — the IMC clocks the whole system to the slowest stick. Combined uplift target: **~50% more usable memory bandwidth** by balancing channels and unlocking the 8-DIMM platform ceiling.

### Goals

- Full symmetric quad-channel — every channel has equal capacity, so the entire RAM range gets 4-way interleave instead of dropping to dual-channel for the unbalanced portion.
- Lift the 2400 MT/s floor; target **2933 MT/s** (the realistic 8-DIMM ceiling on Threadripper 1950X with DOCP).
- 64 GB capacity — sized for ZFS ARC headroom + Postgres + LLM context buffers.
- Stay at 8 DIMMs — capacity per channel matters more than chasing 4-DIMM 3200 MT/s for this workload.

### Current state

| Channel | DIMM 0 | DIMM 1 | Channel total |
|---------|--------|--------|---------------|
| A | 8 GB | 8 GB | 16 GB |
| B | *empty* | 8 GB | 8 GB |
| C | 8 GB | 8 GB | 16 GB |
| D | *empty* | 8 GB | 8 GB |

Total: 48 GB. All 4 channels populated → quad-channel mode is active, but **flex-mode**: the first 32 GB interleaves across all 4 channels (~76 GB/s @ 2400 MT/s); the remaining 16 GB stripes across only A and C (~38 GB/s).

#### Why 2400 MT/s instead of 2666

The Zen 1 IMC runs at JEDEC speed of the slowest installed kit. Mixed kits in this build:

| Part Number | Rating | Status |
|---|---|---|
| `BLS8G4D30AESEK.M8FE1` (Crucial Ballistix Sport LT) | DDR4-3000 | Underclocked to 2400 |
| `CMK16GX4M2A2400C16` (Corsair Vengeance LPX 2400) | DDR4-2400 | **Floor — locks the system at 2400** |
| `CMK16GX4M2B3200C16` (Corsair Vengeance LPX 3200) | DDR4-3200 | Underclocked to 2400 |

`CMK16GX4M2A2400C16` is what's holding everything down — DOCP can't raise the system above the slowest stick's rating.

### Plan — Replace the 2400 kit + add 2 more (≈$80–120)

Pull both `CMK16GX4M2A2400C16` Corsair 2400 sticks. Buy 4× 8GB DDR4-3000+ single-rank sticks; install a matched pair in each freed/empty channel. Per-channel layout in the user's order — both purchased kits are 3000 CL15:

| Channel | DIMM 0 | DIMM 1 | Final |
|---------|--------|--------|-------|
| A | Crucial 3000 CL16 (existing) | Crucial 3000 CL16 (existing — moved from C-DIMM 0) | matched pair |
| B | **NEW Crucial Ballistix `BL8G30C15U4R` 3000 CL15** | **NEW Crucial Ballistix `BL8G30C15U4R` 3000 CL15** | matched pair |
| C | Corsair `CMK16GX4M2B3200C16` 3200 CL16 (existing — moved from D-DIMM 1) | Corsair 3200 CL16 (existing) | matched pair |
| D | **NEW Corsair `CMK16GX4M2B3000C15W` 3000 CL15** | **NEW Corsair `CMK16GX4M2B3000C15W` 3000 CL15** | matched pair |

Each channel ends up with a same-kit pair — Zen 1 IMC trains channels independently, so this maximizes timing stability per channel. Result after DOCP: **64 GB, true symmetric quad-channel, ~2933 MT/s** → ~94 GB/s aggregate.

### Install steps (when the new sticks arrive)

1. Power down, unplug.
2. Pull both Corsair `CMK16GX4M2A2400C16` sticks from **A-DIMM 1** and **B-DIMM 1**.
3. Move existing Crucial 3000 stick from **C-DIMM 0** → **A-DIMM 1**.
4. Move existing Corsair 3200 stick from **D-DIMM 1** → **C-DIMM 0**.
5. Install new Crucial 3000 CL15 pair into **B-DIMM 0 + B-DIMM 1**.
6. Install new Corsair 3000 CL15 white pair into **D-DIMM 0 + D-DIMM 1**.
7. Boot to BIOS → **Load Optimized Defaults** → **Ai Tweaker → Ai Overclock Tuner → DOCP** → save & exit.

### Verify

```bash
free -h
# Total should now read ~58.6 GiB (i.e., 64 GB raw)

sudo dmidecode -t 17 | grep -E "Bank Locator|Locator|Size|Part Number|Configured" | grep -v "No Module"
# Every channel shows 2 populated sticks of the same Part Number; Configured Memory Speed = 2666 or 2933

sudo apt install -y mbw stress-ng

mbw -n 5 1024
# Expected AVG MEMCPY:
#   ~50 GB/s  current (flex-mode @ 2400)
#   ~85+ GB/s true quad-channel @ 2933 (recommended path)

# 10-minute stability soak after BIOS tuning
sudo stress-ng --vm 8 --vm-bytes 80% --timeout 600s --metrics
```

### Risks & notes

- **Why 2933 and not 3000+ with 8 DIMMs**: the Zen 1 (Whitehaven) IMC degrades with rank load. 1 DIMM per channel can hit 3200; 2 DIMMs per channel realistically tops out at 2933 even with 3200-rated sticks. Don't waste money on 3600 kits.
- **Single-rank only**: keep all sticks 8GB single-rank. Mixing single-rank and dual-rank in the same channel can cause boot failures or force the IMC to drop another notch.
- **POST instability**: 8 DIMMs is the most demanding config for the memory controller. If POST fails after enabling DOCP, drop target frequency one step (2933 → 2666) or bump DRAM voltage to 1.35V. Memory Context Restore = ON skips retraining on subsequent boots once stable.
- **No DDR5 path**: Threadripper 1950X is DDR4 only. Any future DDR5 means a platform change — defer indefinitely.

### Decisions

- [ ] Purchase the 2× new 16GB kits (Crucial `BL8G30C15U4R` + Corsair `CMK16GX4M2B3000C15W`)
- [ ] Schedule a 30-minute power-down window to install + tune BIOS
- [ ] Pull the 2× `CMK16GX4M2A2400C16` Corsair sticks
- [ ] Enable DOCP in BIOS, verify ~2933 MT/s under load
- [ ] Verify true quad-channel via `mbw` and run `stress-ng` for 10 min stability soak
- [ ] Update `hardware.md` to reflect 64 GB / 8 sticks / 2933 MT/s / true quad-channel

---

## Convention for future upgrades

When the RAM upgrade lands:
1. Move the "Next upgrade" detail down into a new row in the **Upgrade History** table — date, summary, why.
2. Replace the "Next upgrade" section with the next planned upgrade's detailed plan.
3. Commit. The git history retains the full prior plan if you ever need to reconstruct details.

This keeps `hardware_upgrades.md` short and forward-looking instead of accumulating cruft.
