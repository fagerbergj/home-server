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

## Next upgrade: GPU swap — RTX 3090 → 2× AMD Radeon AI Pro R9700 (CUDA → ROCm)

### Goals

- 64 GB total VRAM (2× 32 GB) for comfortable 70B Q5 inference and headroom for parallel small models, vs. the 3090's 24 GB ceiling that caps at 33B Q4.
- Workstation-class cards with blower coolers and 3-yr warranty, at consumer-card prices (~$1,300 each new vs. ~$8,000 for a single RTX Pro 6000 / ~$4,000 for an RTX 5090).
- Stay within existing case (Define 7 XL) and PSU (1200 W) — no chassis or power upgrade.
- Validate ROCm on this stack before committing to a possible 3rd card later (3-card config would still fit the PSU; 4-card would not).

### Current state

- 1× RTX 3090 (Ampere, 24 GB), PCIe 3.0 x16 slot, NVIDIA proprietary driver, NVIDIA Container Toolkit.
- 5 services + monitoring touch the GPU via `runtime: nvidia` or CUDA images:
    - `llm/` — Ollama (CUDA inference)
    - `photos/` — Immich ML (`release-cuda` image) + Immich server (NVENC video transcode)
    - `plex/` — Plex (NVENC/NVDEC transcode)
    - `audio/` — `pyannote-diarize` (custom image, `nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04` base)
    - `monitoring/` — `nvidia_gpu_exporter` for Prometheus

### Plan

**Phased approach** — install the first R9700 alongside the existing 3090, migrate services one-by-one with the 3090 as a fallback, then swap the 3090 for the second R9700 once everything's validated. Two shutdowns total; only the second is a point of no return.

**Hardware:**
1. **Slot plan** (X399-E SMBIOS labels, top → bottom physical order: PCIEX16_1 / PCIEX4 / PCIEX16_2 / PCIEX16_3 / PCIEX1 / PCIEX16_4):
    - **PCIEX16_1**: 3090 today → R9700 #2 (after shutdown #2). x16 CPU.
    - **PCIEX4**: covered by GPU in PCIEX16_1's 2-slot cooler. Unusable; not needed.
    - **PCIEX16_2**: empty. Provides an airflow gap between the two GPUs once both R9700s are in. x8 CPU.
    - **PCIEX16_3**: empty today → R9700 #1 (after shutdown #1 and final). x16 CPU.
    - **PCIEX1**: covered by GPU in PCIEX16_3. Unusable; not needed.
    - **PCIEX16_4**: HBA (relocated here from PCIEX16_2 due to SFF-8643 cable clearance — routing 4 fanout cables out of a middle-board slot past GPU coolers wasn't viable). x8 CPU. No further relocation needed for the 2-card plan.
2. **Current layout** (visually confirmed): 3090 in PCIEX16_1 (top), HBA in PCIEX16_4 (bottom), other slots empty.
3. Shutdown #1: install 1× R9700 in **PCIEX16_3** (the empty x16 slot in the middle). 3090 stays in PCIEX16_1.
4. Migrate services with the 3090 still live as a CUDA fallback for anything that breaks.
5. Shutdown #2: pull 3090 from PCIEX16_1, install 2nd R9700 there. List 3090 (~$900).
6. (3rd-card future is more constrained — see Decisions.)
7. Each card needs 2× 8-pin PCIe; 1200 W Corsair has the leads.

**HBA bandwidth and thermals**: PCIEX16_4 = x8 CPU (~7.9 GB/s) — same bandwidth as the prior PCIEX16_2 position, just relocated. Thermally this position is actually *better* than the sandwich position would have been: HBA sits at the bottom of the case below the GPU stack, in the path of front intake fans, with no GPU cooler dumping heat onto it. **Fan-shroud caveat**: the upward-extending shroud (e.g. the Printables 9300-16i Noctua design) is still **not viable** — GPU #1 in PCIEX16_3 hangs into PCIEX1 (the slot above the HBA), so the shroud's 2nd-slot footprint would collide. With the improved airflow at the bottom slot the shroud may not be needed at all; if it does become necessary under load, fall back to a side-mounted fan (zip-tie or magnetic mount) blowing across the heatsink.

**Software:**
1. Install ROCm 6.x stack alongside existing NVIDIA driver — both coexist on Linux (separate kernel modules, separate device nodes, no contention for compute).
2. Per-service migration (see "Install steps") — Ollama first to validate end-to-end, custom pyannote image last because it's a full Dockerfile rebuild.
3. Purge NVIDIA stack only after the second R9700 is in and all services have been running clean on ROCm for at least a week.

### Install steps

Order intentional: easiest service first, custom build last, monitoring early so both GPUs are observable throughout.

1. **Pre-flight on existing setup**
    - Confirm 3090 slot count (Founders/blower = 2-slot, most AIB = 3-slot). If 3-slot, the dual-card validation phase isn't possible without HBA reshuffle — skip straight to a single-window swap.
    - Snapshot `/` for rollback (LVM or `timeshift`).
    - `git checkout -b gpu-rocm-migration` and stage doc changes alongside the swap so they land together.
2. **Shutdown #1: install 1× R9700 alongside 3090**
    - Boot, expect both cards visible in `lspci`.
3. **Install ROCm alongside NVIDIA**
    - Don't purge anything NVIDIA yet.
    - Install ROCm per AMD's Ubuntu 24.04 instructions (`amdgpu-install --usecase=rocm,dkms`)
    - Add user to `render` and `video` groups
    - Reboot, verify both `nvidia-smi` (3090) and `rocm-smi` (R9700) work side-by-side
4. **Monitoring first** (`monitoring/`) — add `amd-smi-exporter` alongside the existing `nvidia_gpu_exporter`. Both run in parallel through the entire migration so you can watch GPU temps, VRAM, and load on both cards as services move. Add Grafana panels for the AMD metrics; leave the NVIDIA panels in place.
5. **Service migration**, in order — for each, stand up the ROCm version side-by-side with the CUDA version where possible, validate, then cut over:
    1. **Ollama** (`llm/`) — bring up a parallel `ollama-rocm` container pointed at the R9700 (`devices: [/dev/kfd, /dev/dri]`, `group_add: [video, render]`, image `ollama/ollama:rocm`) on a different port. Pull a 32B coding model (e.g. Qwen2.5-Coder-32B Q5), validate. Once happy, point Open WebUI at the new endpoint and remove the CUDA Ollama. Note: 70B target can't be validated until shutdown #2 — see Risks.
    2. **Plex** (`plex/`) — drop `runtime: nvidia`, mount `/dev/dri`. Plex UI → Transcoder → switch HW accel from NVENC to VAAPI. Force a transcode, confirm `(hw)`.
    3. **Immich server + ML** (`photos/`) — server: drop nvidia runtime, mount `/dev/dri`, set transcoder to VAAPI. ML: image tag `release-cuda` → `release-rocm`, swap device block. Expect a multi-hour ML re-extraction on first run.
    4. **pyannote-diarize** (`audio/`) — rebuild Dockerfile on `rocm/pytorch:latest` base. Tag the existing CUDA image as `pyannote-diarize:cuda-fallback` first so you can roll back if the rebuild misbehaves. Test against a known transcription.
6. **Soak period** — run all migrated services for at least a week on the single R9700 with the 3090 idle. If anything is unstable, fall back to CUDA on the 3090 while debugging. The 3090 stays in the box as insurance.
7. **Shutdown #2: 3090 → 2nd R9700**
    - Pull 3090, install 2nd R9700.
    - Boot, verify `rocm-smi` lists both R9700s.
    - **Now** validate the 70B target on Ollama (tensor parallel across 2 cards via PCIe).
    - List 3090 for sale (~$900).
8. **NVIDIA cleanup**
    - `sudo apt purge 'nvidia-*' 'libnvidia-*' nvidia-container-toolkit`
    - Remove `nvidia_gpu_exporter` from `monitoring/docker-compose.yml`; remove its Grafana panels.
    - Blacklist `nouveau` if it tries to load on the AMD-only system.
9. **Doc cleanup**
    - Update each service's docs as you migrate it (in lockstep with step 5), not at the end — easier to write accurate docs while the change is fresh.
    - Final pass after step 8: `setup.md` Phase 3, `scripts/setup/phase5-docker.sh` and its bats tests, top-level `README.md`. See "Doc + script inventory" below.

### Verify

- `rocm-smi` shows both cards healthy, drivers loaded, no ECC/PCIe errors
- `docker run --rm --device=/dev/kfd --device=/dev/dri rocm/rocm-terminal rocm-smi` works (Docker can see GPUs)
- Ollama: `ollama ps` shows 100% GPU on a 70B Q5 model, tokens/sec sanity-check
- Plex: forced transcode shows `(hw)` in dashboard
- Immich: video preview generates without CPU spike; ML re-extraction completes
- pyannote: known-good test clip produces identical speaker count to pre-migration baseline
- Grafana: GPU panels populated with new metric names
- All compose stacks come up clean (`docker compose ps` healthy across `llm/`, `photos/`, `plex/`, `audio/`, `monitoring/`)

### Risks & notes

- **3090 slot count gates the phased plan.** With GPUs targeted for PCIEX16_1 and PCIEX16_3 (PCIEX4 + PCIEX16_2 between them, both intentionally unoccupied), a 2-slot 3090 in PCIEX16_1 covers only PCIEX4 and leaves PCIEX16_3 free for the first R9700. A 3-slot 3090 (most AIB cards: EVGA FTW3, ASUS Strix) spans PCIEX16_1 + PCIEX4 + PCIEX16_2, which doesn't physically block PCIEX16_3 *electrically* but kills airflow into it. Confirm card thickness before ordering the first R9700. If 3-slot, fall back to a single-window swap of both cards at once.
- **Single-card validation can't cover the 70B target.** During the dual-card phase only one R9700 (32 GB) is available for ROCm workloads, so 70B Q5 (~50 GB) doesn't fit until shutdown #2. Smaller models (32B Q5 fits comfortably; 24B-class fits with room) validate that ROCm + Ollama itself works. Tensor parallelism across 2 R9700s on PCIe is the one piece you only get to test after shutdown #2 — known unknown. If TP turns out broken, fallback options are: debug it (ROCm 2-card TP is generally fine, but this hardware specifically is unverified), or stop at one card and reassess.
- **pyannote rebuild is the rough one.** ROCm pytorch wheels exist but pyannote's transitive deps (SpeechBrain, torch-audiomentations) sometimes assume CUDA-only kernels. Budget half a day, expect to pin versions. Mitigation: tag the CUDA image as `cuda-fallback` before rebuilding so rollback is one compose edit.
- **Immich ML re-extraction** is unavoidable on the image swap — the embedding format is the same but the container revalidates everything on first boot. Hours, not days, but plan around it.
- **Mixed-vendor coexistence is fine for compute, not for displays.** NVIDIA and AMD drivers run cleanly side-by-side on Linux for compute workloads (separate kernel modules, separate device nodes). The headless server has no display contention to worry about. Apps that auto-select "first GPU" need explicit device selection during the dual-card phase, but every service in this stack is configured with explicit device targeting in compose.
- **Slot spacing**: R9700 is a 2-slot blower. Final 2-card layout puts GPUs in PCIEX16_1 and PCIEX16_3 with PCIEX16_2 empty between them (good for airflow), and HBA at PCIEX16_4 (bottom, isolated from the GPU stack). Blowers exhaust rear-out, so heat doesn't pool around the HBA.
- **Power (2-card final)**: 2× 300 W GPUs + 1950X (180 W TDP, ~80 W realistic during inference) + system (~80 W) ≈ 880 W theoretical peak / ~660 W realistic. 1200 W PSU has comfortable headroom. During the dual-card phase (3090 + 1× R9700) peaks are well under 1000 W since both cards aren't loaded at once.
- **Power (if/when a 3rd R9700 lands)**: theoretical peak ~1180 W (3× 300 W GPUs + full TDP CPU + system), but inference workloads keep the CPU at ~80 W and GPUs at ~700–800 W sustained — realistic peak is ~960 W with ~1100 W transient bursts during simultaneous prefill across all 3 cards. 80% sustained load is in the 1200 W PSU's efficiency sweet spot. Action: baseline actual draw during the 2-card phase with a smart plug (Kasa KP125M, ~$15) — gives real numbers vs. TDP math. Watch for PSU canaries (coil whine under prefill, reboots under load, capacitor smell). 1600 W upgrade stays in the back pocket as a "if it becomes a problem" move, not a prerequisite for 3 cards.
- **ROCm version pinning**: ROCm minor versions occasionally break compatibility with pytorch wheels. Pin both in `audio/pyannote-diarize/requirements.txt` and Ollama's image tag.

### Doc + script inventory — what changes for ROCm

Every place CUDA / NVIDIA is mentioned, in update order:

| File | Current content | Action |
|---|---|---|
| `setup.md` line 132–159 | "Phase 3 — NVIDIA Drivers" — blacklist nouveau, install `nvidia-driver-535`, verify with `nvidia-smi` | Rewrite as "Phase 3 — AMD GPU Drivers (ROCm)" — `amdgpu-install --usecase=rocm,dkms`, verify with `rocm-smi` |
| `setup.md` line 178 | `nvtop` command | Keep — `nvtop` supports AMD via libdrm; still works |
| `setup.md` line 388–405 | NVIDIA Container Toolkit install + `--gpus all` smoke test | Replace with ROCm Docker access pattern: `--device=/dev/kfd --device=/dev/dri`, smoke test with `rocm/rocm-terminal` |
| `README.md` line 29 | "Ubuntu Server 24.04 LTS — chosen for strong NVIDIA/CUDA driver support" | Reword: "…chosen for strong GPU driver support (ROCm 6.x and NVIDIA both first-class on 24.04)" |
| `README.md` line 65, 67 | "NVIDIA Drivers" / "Docker + NVIDIA Container Toolkit" in phase list | "AMD GPU Drivers (ROCm)" / "Docker + ROCm device access" |
| `scripts/setup/phase5-docker.sh` line 27–41 | nvidia-container-toolkit install + `--gpus all` smoke test | Replace with no-op (ROCm needs no separate Docker toolkit; `/dev/kfd` + `/dev/dri` passthrough is built-in) |
| `scripts/setup/test/phase5-docker.bats` line 72–117 | bats stubs and assertions for `nvidia-ctk` | Rewrite tests against the simplified ROCm path; drop the `nvidia-ctk` mock |
| `llm/README.md` line 3 | "RTX 3090 (24GB VRAM)" | "2× AMD Radeon AI Pro R9700 (32 GB VRAM each, 64 GB total)" |
| `llm/README.md` line 71, 79 | 3090 / context examples | Re-baseline against R9700; 70B Q5 numbers replace the 33B Q4 framing |
| `llm/README.md` line 141–142 | "RTX 3090 24GB VRAM — expect ~20–50 tokens/sec…" + "Plex NVENC and LLM share GPU" | Rewrite for R9700 throughput; note Plex is now on a separate VAAPI path so no GPU contention with Ollama |
| `llm/setup.md` line 48–52 | "Check GPU is being used" | Update command examples to `rocm-smi` instead of `nvidia-smi` if any are referenced |
| `audio/README.md` line 9, 12, 18, 19, 79 | "GPU-accelerated", "shared with Ollama", "NVIDIA GPU with driver supporting CUDA 12.1+", "NVIDIA Container Toolkit", "3090: ~10% of audio length" | Rewrite for ROCm: drop CUDA prerequisites, note ROCm pytorch base, re-baseline diarization throughput on R9700 |
| `audio/setup.md` line 7, 8, 86 | CUDA 12.1+ prereq, NVIDIA Container Toolkit, "CUDA driver too old" troubleshooting | Replace with ROCm 6.x prereq, drop toolkit line, replace troubleshooting with ROCm equivalents (`rocm-smi` checks, kernel module load, `render`/`video` group membership) |
| `audio/pyannote-diarize/Dockerfile` line 2 | `FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04` | `FROM rocm/pytorch:latest` (pin to specific ROCm version once tested) |
| `audio/pyannote-diarize/requirements.txt` | torch + torchaudio pinned to CUDA wheels | Switch to ROCm-compatible torch wheels (PyTorch publishes ROCm builds — different index URL) |
| `photos/setup.md` line 44–54 | "Phase 5 — Enable NVENC hardware transcoding", set Accelerator API to NVENC, verify with `nvidia-smi dmon` | Rewrite for VAAPI: set Accelerator API to `Quick Sync`/`VAAPI`, verify with `radeontop` or `intel_gpu_top`-style AMD equivalent |
| `photos/README.md` line 20–24 | "GPU Acceleration (ML) — RTX 3090 for face detection… nvidia-container-toolkit" | Rewrite for ROCm: cards used for ML, no toolkit needed, `/dev/kfd` + `/dev/dri` mounted |
| `monitoring/README.md` line 7 | "NVIDIA GPU Exporter — GPU utilization, VRAM, temperature" | "AMD GPU Exporter (`amd-smi-exporter`) — same metrics, different exporter" |
| `plex/setup.md` line 49 | "If you have Plex Pass, verify hardware transcoding" — vendor-agnostic, no change needed | No change |
| `plex/README.md` line 19–25 | "Hardware Transcoding" section — vendor-agnostic copy | Optionally add a one-liner: "transcode path is VAAPI on AMD" |
| `hardware.md` line 16 | "RTX 3090 (Ampere, 24GB VRAM)…" | After install: "2× AMD Radeon AI Pro R9700 (RDNA 4, 32 GB VRAM each, 64 GB total) — ROCm 6.x" |

### Decisions

- **2 cards, not 4.** 4× R9700 = 1200 W just for GPUs, exceeds 1200 W PSU. 4 cards also displaces the HBA from its x8 CPU slot, defeating the entire reason X399 was picked. Stated workloads (coding agents, security automation) are well-served by 64 GB and don't need 128 GB.
- **No PSU upgrade.** 880 W peak with 2 cards; existing 1200 W stays.
- **Sell the 3090, don't keep it as a "secondary".** Mixing CUDA + ROCm in one box is a configuration headache and the 3090 doesn't earn its slot once the R9700s are doing inference. Recovers ~$900 of the ~$2,600 cost.
- **Ollama first, pyannote last** in the migration order. Ollama image swap is the cleanest validation that ROCm works end-to-end; pyannote rebuild is the longest pole and gets done after the rest is stable.
- **3rd card path is now constrained by HBA cable routing.** Validate the 2-card config for a few months. If 64 GB feels constraining and ROCm hasn't been a nightmare, *and* you're willing to revisit the HBA cabling, add card #3. If ROCm has been painful, pivot to a single Pro 6000 instead and accept the cost.
- **If/when a 3rd R9700 lands, the HBA has to move to PCIEX16_2.** That's the only x8+ slot that won't be occupied by a GPU in the 3-card layout (R9700s in PCIEX16_1 / PCIEX16_3 / PCIEX16_4). PCIEX16_2 is the same middle-board position that was already ruled out once for cable clearance, so this requires solving the cable routing problem — likely with right-angle SFF-8643 adapters (~$8 each) or shorter custom-length cables. Without that, 3 cards isn't achievable at full lanes. Riser cable is still rejected for maintenance reasons (extra failure point, awkward servicing, finicky cable seating). Cooling mitigation if it happens: add a 3rd front intake (140 mm, fills the open mount in the Define 7 XL) and bump the front-fan base curve to feed the GPU stack. Middle GPU (R9700 #2 in PCIEX16_3) becomes the thermal pinch point in a 3-card config; monitor via `rocm-smi`. **HBA active cooling**: heatsink-top shrouds remain blocked by adjacent GPU coolers in any multi-GPU config — side-blowing fan if needed.

---

## Convention for future upgrades

When the RAM upgrade lands:
1. Move the "Next upgrade" detail down into a new row in the **Upgrade History** table — date, summary, why.
2. Replace the "Next upgrade" section with the next planned upgrade's detailed plan.
3. Commit. The git history retains the full prior plan if you ever need to reconstruct details.

This keeps `hardware_upgrades.md` short and forward-looking instead of accumulating cruft.
