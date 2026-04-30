# RAM Upgrade Plan — Threadripper 1950X / X399-E

Migration from a mixed 6× 8GB kit at 2400 MT/s (flex-mode quad-channel) to a balanced 8× 8GB or 4× 16GB layout in true quad-channel.

## Goals

- Full symmetric quad-channel (every channel populated equally) so the entire RAM range gets 4-way interleave instead of dropping to dual-channel for the unbalanced portion
- Eliminate the 2400 MT/s ceiling forced by the slowest kit
- 64 GB capacity (sized for ZFS ARC headroom + Postgres + future LLM context buffers)

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

Two viable paths, depending on budget and how much performance matters.

### Option A — Cheapest path: add 2× 8GB DDR4-2400 (≈$30–40)

Buy 2 more 8GB DDR4-2400 sticks (any reputable brand) and slot them into Channel B DIMM 0 and Channel D DIMM 0.

| Channel | DIMM 0 | DIMM 1 | Channel total |
|---------|--------|--------|---------------|
| A | 8 GB | 8 GB | 16 GB |
| B | **8 GB (new)** | 8 GB | 16 GB |
| C | 8 GB | 8 GB | 16 GB |
| D | **8 GB (new)** | 8 GB | 16 GB |

Result: **64 GB, true quad-channel, 2400 MT/s**. Bandwidth jumps from flex (~60 GB/s effective) to full quad (~76 GB/s) and capacity goes up 33%. Speed unchanged — the 2400 kit still floors it.

### Option B — Cleanest path: replace the Corsair 2400 kit + add 2 more (≈$80–120)

Pull the 2× `CMK16GX4M2A2400C16` sticks (the bottleneck), buy 4× 8GB DDR4-3000 (matching the existing Crucial Ballistix Sport LT spec is ideal — same SKU `BLS8G4D30AESEK.M8FE1` if still available), populate all 8 slots.

Result: **64 GB, true quad-channel, 2933 MT/s** (Threadripper 1950X tops out at 2933 with DOCP on a balanced 2-DIMM-per-channel config; 3000-rated sticks will run at 2933).

Memory bandwidth jumps from ~76 GB/s (Option A) to ~94 GB/s — ~24% more for ~3× the cost.

### Option C — Future / extreme: 8× 16GB matched kit (≈$300+)

128 GB, true quad-channel, 2933+ MT/s. Overkill for current workloads but useful if LLM context windows grow or Postgres datasets exceed 32 GB working set. Defer indefinitely.

## Recommended Path

**Option A now, Option B if/when capacity or LLM workloads demand it.** The marginal bandwidth gain from B vs A doesn't move the needle for Plex/Immich/torrents/Docker — those are I/O bound. LLM inference is GPU-bound on the RTX 3090, not CPU-memory-bound. ZFS ARC scales by capacity, not bandwidth.

If you ever notice the system stalling on memory pressure (high `kswapd0` activity, swap thrashing during LLM loads), that's the signal to jump to B or C.

## Implementation — Option A

### Pre-purchase checklist

```bash
# Confirm the bottleneck kit's exact SKU
sudo dmidecode -t 17 | grep -E "Manufacturer|Part Number|Speed:"

# Confirm slot layout (which DIMMs are empty)
sudo dmidecode -t 17 | grep -E "Bank Locator|Locator|Size" | grep -v "No Module"
```

Order 2× 8GB DDR4-2400 — anything reputable. Doesn't need to match the existing kits' brand; only the **rated speed and capacity** matter for system-wide compatibility. Reasonable picks:

- Corsair Vengeance LPX `CMV8GX4M1A2400C16` (single 8GB, 2400)
- Crucial Ballistix `BLS8G4D240FSB`
- Kingston ValueRAM `KVR24N17S8/8`

### Install

1. Power down. Unplug.
2. Open the case, locate empty slots: **DIMM_B1** (Channel B DIMM 0) and **DIMM_D1** (Channel D DIMM 0). Refer to the X399-E manual for slot labels — ASUS conventionally labels them `DIMM_A1, DIMM_A2, DIMM_B1, DIMM_B2, ...` where A1 is closer to the CPU.
3. Insert sticks, ensure both retention clips snap closed.
4. Boot.

### Verify

```bash
free -h
# Total should now read ~58.6 GiB (i.e., 64 GB raw)

sudo dmidecode -t 17 | grep -E "Bank Locator|Size" | grep -v "No Module"
# Every channel should now show 2 sticks
```

Look at every motherboard channel light during POST — ASUS X399 boards show DRAM POST LEDs; if any flash red on boot the new sticks aren't seated or are incompatible. Reseat or pull and try one at a time to isolate.

### Confirm true quad-channel

Memory bandwidth benchmark:

```bash
sudo apt install -y mbw
mbw -n 5 1024
# Look at AVG MEMCPY — should be roughly:
#   ~50 GB/s flex-mode (current)
#   ~70+ GB/s true quad-channel @ 2400
```

Or with `sysbench`:

```bash
sudo apt install -y sysbench
sysbench memory --memory-block-size=1M --memory-total-size=64G --threads=8 run
# Look at "transferred" rate in MB/sec
```

## Risks & Notes

- **Mixed-rank or mixed-density sticks**: as long as all sticks are 8GB single-rank DDR4-2400, the controller will run all of them at the same timings. Mixing single-rank and dual-rank in the same channel can cause boot failures.
- **DOCP/XMP**: with the 2400 kit installed, DOCP doesn't help — the 2400 kit's SPD has no DOCP profile above 2400. After Option B (2400 kit removed), enable DOCP in BIOS to push the remaining sticks to their rated 3000 (which Threadripper will clock down to 2933).
- **POST instability**: 8 DIMMs populated is the most demanding config for the memory controller. If POST takes longer or RAM training fails on first boot, increase **DRAM Voltage** by +0.05V (1.20 → 1.25) in BIOS or run **Memory Context Restore** to skip retraining on subsequent boots.
- **No DDR5 path**: Threadripper 1950X is DDR4 only. Any future jump to DDR5 means a platform change (Threadripper 7000 / sTR5 or Ryzen 9000 / AM5) — defer indefinitely.

## Decisions

- [ ] Purchase 2× 8GB DDR4-2400 sticks (Option A)
- [ ] Schedule a 30-minute power-down window to install
- [ ] Verify true quad-channel via `mbw` or `sysbench memory`
- [ ] Update `hardware.md` to reflect 64 GB / 8 sticks / true quad-channel
