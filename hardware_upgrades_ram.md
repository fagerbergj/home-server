# RAM Upgrade Plan — Threadripper 1950X / X399-E

Migration from a mixed 6× 8GB kit at 2400 MT/s (flex-mode quad-channel) to a balanced **8× 8GB layout running at ~2933 MT/s** in true quad-channel.

## Goals

- Full symmetric quad-channel (every channel populated equally) so the entire RAM range gets 4-way interleave instead of dropping to dual-channel for the unbalanced portion
- Lift the 2400 MT/s floor forced by the slowest kit; target **2933 MT/s** (the realistic 8-DIMM ceiling on Threadripper 1950X with DOCP)
- 64 GB capacity (sized for ZFS ARC headroom + Postgres + future LLM context buffers)
- Stay at 8 DIMMs — capacity per channel matters more than chasing 4-DIMM 3200 MT/s for this workload

## Current State

The system has 6 DIMMs from 3 different kits, populating Channels A and C fully but only DIMM_1 on Channels B and D:

| Channel | DIMM 0 | DIMM 1 | Channel total |
|---------|--------|--------|---------------|
| A | 8 GB | 8 GB | 16 GB |
| B | *empty* | 8 GB | 8 GB |
| C | 8 GB | 8 GB | 16 GB |
| D | *empty* | 8 GB | 8 GB |

Total: 48 GB. All 4 channels populated → quad-channel mode IS active, but **flex-mode**: the first 32 GB interleaves across all 4 channels (full quad-channel bandwidth ~ 76 GB/s @ 2400 MT/s); the remaining 16 GB stripes across only A and C (dual-channel ~ 38 GB/s).

### Why 2400 MT/s instead of 2666

The Threadripper 1950X memory controller runs at JEDEC speed of the slowest installed kit. Mixed kits in this build:

| Part Number | Rating | Status |
|---|---|---|
| `BLS8G4D30AESEK.M8FE1` (Crucial Ballistix Sport LT) | DDR4-3000 | Underclocked to 2400 |
| `CMK16GX4M2A2400C16` (Corsair Vengeance LPX 2400) | DDR4-2400 | **Floor — locks the system at 2400** |
| `CMK16GX4M2B3200C16` (Corsair Vengeance LPX 3200) | DDR4-3200 | Underclocked to 2400 |

`CMK16GX4M2A2400C16` is what's holding everything down. Even after enabling DOCP, the system can't run faster than the slowest stick's rating — the BIOS will refuse to boot at higher speeds, or fall back to JEDEC.

## Target State

The 8-DIMM platform ceiling on Threadripper 1950X is ~2933 MT/s with DOCP. Going from current 2400 to 2933 unlocks ~22% more aggregate bandwidth — and balancing the channel config on top adds another ~25% by eliminating flex-mode. Combined uplift: **~50% more usable memory bandwidth** vs the current state.

### Recommended — Replace the 2400 kit + add 2 more (≈$80–120)

The two `CMK16GX4M2A2400C16` sticks are what's locking the entire system to 2400 MT/s. Pulling them and swapping in faster sticks unlocks the platform ceiling.

1. Pull both `CMK16GX4M2A2400C16` Corsair 2400 sticks
2. Buy **4× 8GB DDR4-3000+** sticks — matching the existing Crucial Ballistix Sport LT (`BLS8G4D30AESEK.M8FE1`) is ideal but not required; any 3000–3200 single-rank 8GB stick works
3. Populate all 8 slots:

| Channel | DIMM 0 | DIMM 1 | Channel total |
|---------|--------|--------|---------------|
| A | 8 GB (existing) | 8 GB (existing) | 16 GB |
| B | **8 GB (new)** | **8 GB (new, replacing 2400)** | 16 GB |
| C | 8 GB (existing) | 8 GB (existing) | 16 GB |
| D | **8 GB (new)** | **8 GB (new, replacing 2400)** | 16 GB |

4. Enable **DOCP** in BIOS. System negotiates down from each kit's 3000–3200 rating to ~2933 — the realistic 8-DIMM ceiling on the Zen 1 IMC.

Result: **64 GB, true quad-channel, ~2933 MT/s** → ~94 GB/s aggregate.

### Fallback — Add 2× 2400 sticks if budget is tight (≈$30–40)

If you don't want to spend on the kit replacement now, just add 2× 8GB DDR4-2400 in the empty B0 / D0 slots. You get true quad-channel (eliminates flex-mode) but stay capped at 2400 MT/s.

Result: **64 GB, true quad-channel, 2400 MT/s** → ~76 GB/s aggregate.

This is a stepping stone — you can do the full kit swap later without wasting hardware (the new 2400 sticks won't fit the final 2933 plan since they'd re-introduce the bottleneck, so this path only makes sense if cost is the constraint and the upgrade window is long).

### Defer — 8× 16GB at 2933 MT/s (≈$300+)

128 GB, true quad-channel, ~2933 MT/s. Defer indefinitely. Useful only if LLM context windows grow or Postgres working set exceeds 32 GB. ZFS ARC will happily consume any extra RAM but with diminishing returns past 32 GB ARC for media-mostly workloads.

## Recommended Path

**Replace the 2400 kit + add 2 more.** Bandwidth uplift is significant (~50% over current state when you combine the channel-balance fix with the speed uplift), cost is modest, and you avoid wasted hardware spend on the fallback.

The fallback only makes sense if you literally have $30 to spend right now and not $100. Plex/Immich/torrents/Docker won't notice the difference, but LLM token throughput on CPU and Postgres analytical queries do measurably scale with memory bandwidth.

## Implementation

### Pre-purchase checklist

```bash
# Snapshot current SKUs and serials so you can confirm which sticks to pull
sudo dmidecode -t 17 | grep -E "Manufacturer|Part Number|Serial Number|Speed:"

# Confirm slot layout
sudo dmidecode -t 17 | grep -E "Bank Locator|Locator|Size" | grep -v "No Module"
```

Order 4× 8GB DDR4-3000+ single-rank sticks. Matching the existing Crucial Ballistix Sport LT SKU is the cleanest option:

- **Crucial Ballistix Sport LT `BLS8G4D30AESEK.M8FE1`** (matches existing 2 sticks)

If unavailable, any reputable 8GB DDR4-3000 or DDR4-3200 single-rank kit works — the system runs at the lowest common denominator's rated speed (2933 max on Threadripper). Reasonable alternatives:

- G.Skill Ripjaws V `F4-3200C16D-16GVKB` (16GB kit = 2 sticks)
- Corsair Vengeance LPX `CMK16GX4M2D3000C16` (16GB kit = 2 sticks, 3000 MT/s)

Avoid dual-rank sticks (typically 16GB+ in a single stick) — they'll force the IMC to clock down further when paired 2-per-channel.

### Install

1. Power down. Unplug.
2. Open the case. Identify the 2× `CMK16GX4M2A2400C16` Corsair sticks by serial — match against the dmidecode snapshot. They're in the populated DIMM_1 slots of two channels (probably B and D given the current layout).
3. Pull the 2 Corsair 2400 sticks. Set aside or sell.
4. Install the 4 new sticks into all empty slots: **DIMM_B1, DIMM_B2, DIMM_D1, DIMM_D2** (or wherever the empties + the 2 you just pulled live). Reference the X399-E manual for slot labels — ASUS conventionally labels them `DIMM_A1, DIMM_A2, DIMM_B1, DIMM_B2, ...`.
5. Ensure all retention clips snap closed.
6. Boot into BIOS.

### BIOS

1. **Load Optimized Defaults** first to clear any stale memory training from the old config.
2. Navigate to **Ai Tweaker → Ai Overclock Tuner → DOCP** (or DOCP Standard / DOCP I, depending on BIOS version). DOCP is ASUS's name for XMP.
3. The BIOS will read the SPD profile from one of the new sticks and propose a frequency. With 8 DIMMs populated and Zen 1 IMC, expect it to land at **2666–2933**. Save and exit.
4. First boot after enabling DOCP can take 30–90 seconds while the IMC retrains. If it fails to POST, the board will fall back to JEDEC defaults (2133) — re-enter BIOS, drop the target speed by 1 step (e.g., 2933 → 2666), retry.

### Verify

```bash
free -h
# Total should now read ~58.6 GiB (i.e., 64 GB raw)

sudo dmidecode -t 17 | grep -E "Bank Locator|Size|Configured Memory Speed" | grep -v "No Module"
# Every channel should show 2 populated sticks; Configured Memory Speed should be 2666 or 2933 MT/s
```

### Confirm true quad-channel + speed uplift

Memory bandwidth benchmarks:

```bash
sudo apt install -y mbw sysbench

# Sequential memcpy throughput
mbw -n 5 1024
# Expected AVG MEMCPY:
#   ~50 GB/s  current (flex-mode @ 2400)
#   ~70 GB/s  true quad-channel @ 2400 (fallback path)
#   ~85+ GB/s true quad-channel @ 2933 (recommended path)

# Synthetic memory benchmark
sysbench memory --memory-block-size=1M --memory-total-size=64G --threads=8 run
# Look at "transferred" rate in MB/sec
```

Stability check after BIOS tuning:

```bash
sudo apt install -y stress-ng
sudo stress-ng --vm 8 --vm-bytes 80% --timeout 600s --metrics
# 10 minutes of memory pressure — if the system survives without errors or
# corrected ECC events, the new clock is stable.
```

## Risks & Notes

- **Why 2933 and not 3000+ with 8 DIMMs**: the Zen 1 (Whitehaven) IMC degrades with rank load. 1 DIMM per channel can hit 3200; 2 DIMMs per channel realistically tops out at 2933 even with 3200-rated sticks. Don't waste money on 3600 kits — the IMC won't run them at rated speed in this config.
- **Mixed-rank or mixed-density sticks**: keep all sticks at 8GB single-rank for predictable behavior. Mixing single-rank and dual-rank in the same channel can cause boot failures or force the IMC to drop another notch.
- **DOCP/XMP**: with the 2400 kit removed, enable DOCP in BIOS. The 3000–3200 kits will clock down to 2933 (Zen 1 8-DIMM ceiling) automatically — that's normal, not a failure mode.
- **POST instability**: 8 DIMMs is the most demanding config for the memory controller. If POST takes longer or RAM training fails on first boot, drop the target frequency one step (2933 → 2666) or bump **DRAM Voltage** to 1.35V in BIOS. **Memory Context Restore** = ON skips retraining on subsequent boots once stable.
- **No DDR5 path**: Threadripper 1950X is DDR4 only. Future DDR5 means a platform change (Threadripper 7000 / sTR5 or Ryzen 9000 / AM5) — defer indefinitely.

## Decisions

- [ ] Purchase 4× 8GB DDR4-3000+ single-rank sticks (matching `BLS8G4D30AESEK.M8FE1` ideally)
- [ ] Schedule a 30-minute power-down window to install + tune BIOS
- [ ] Pull the 2× `CMK16GX4M2A2400C16` Corsair sticks
- [ ] Enable DOCP in BIOS, verify ~2933 MT/s under load
- [ ] Verify true quad-channel via `mbw` and run `stress-ng` for 10 min stability soak
- [ ] Update `hardware.md` to reflect 64 GB / 8 sticks / 2933 MT/s / true quad-channel
