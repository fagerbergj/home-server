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
| 2026-04-30 | **Drives.** Storage: mdadm/ext4 → ZFS (`media` RAIDZ2 + `personal` mirror) on LSI 9300-16i HBA.<br>+4× 26TB Seagate Exos + 2× 8TB Dell J7W80; retired all old HDDs.<br>`plex03` (ADATA) → `/mnt/cache` for Ollama models. | ZFS for integrity + ~46 TiB capacity + scrubbing. Single HBA replaces mixed mobo SATA + cheap expansion card. |
| 2026-04-30 | **Platform.** Motherboard B550 Eagle WIFI6 → ASUS ROG Strix X399-E.<br>CPU Ryzen 5 5500 → Threadripper 1950X.<br>RAM 32GB → 48GB DDR4 (mixed kits).<br>Cooler: stock Wraith → DeepCool LT720 360mm AIO. | Done bundled with the drive upgrade for PCIe lanes — B550 caps the HBA at x1 (~985 MB/s); X399 puts it on x8 (~7.9 GB/s). Threadripper sTR4 mandates the AIO; stock Wraith doesn't fit the socket. |
| 2026-05-06 | RAM 48 GB mixed (16/8/16/8 flex-mode @ 2400 MT/s) → 64 GB matched (8× 8GB, true symmetric quad-channel @ 3000 MT/s, VDIMM 1.35 V).<br>Pulled 2× Corsair `CMK16GX4M2A2400C16` 2400; added 2× Crucial Ballistix `BL8G30C15U4R` 3000 CL15 + 2× Corsair `CMK16GX4M2B3000C15W` 3000 CL15.<br>Final layout: A = existing Crucial 3000 CL16 pair, B = existing Corsair 3200 CL16 pair, C = new Corsair 3000 CL15 pair, D = new Crucial Ballistix 3000 CL15 pair. | The 2400 Corsair kit was clocking the whole IMC to its JEDEC floor; removing it and rebalancing to a matched pair per channel unlocks true quad-channel interleave across all 64 GB. Trained at 3000 MT/s rather than the planned 2933 — IMC turned out healthier than typical for an 8-DIMM Zen 1 config. ~22% memory bandwidth uplift for ZFS ARC, page cache, and Postgres. |

Each completed upgrade's full details and rationale live in the git history of this file (`git log -- hardware_upgrades.md`). Re-create as needed.

---

## Next upgrade: _TBD_

No upgrade currently planned. When the next one is scoped, replace this section with a detailed plan following the structure of prior entries (Goals / Current state / Plan / Install steps / Verify / Risks & notes / Decisions).

---

## Convention for future upgrades

When the RAM upgrade lands:
1. Move the "Next upgrade" detail down into a new row in the **Upgrade History** table — date, summary, why.
2. Replace the "Next upgrade" section with the next planned upgrade's detailed plan.
3. Commit. The git history retains the full prior plan if you ever need to reconstruct details.

This keeps `hardware_upgrades.md` short and forward-looking instead of accumulating cruft.
