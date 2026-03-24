# Hardware Upgrade Plan

## Phase 1 — AM4 Platform Swap

Replace the Sandy Bridge platform with AM4 hardware already owned.

### Hardware in hand
| Component | Details |
|-----------|---------|
| Motherboard | MSI B350 Tomahawk |
| RAM | 16GB DDR4 |
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

## Phase 3 — GPU Upgrade

**Priority:** After Phase 1 — more VRAM is the main bottleneck for running larger LLMs.

### Target: RTX 5060 Ti 16GB
- 16GB VRAM unlocks larger models (13B+ quantized, potentially 30B at lower quant)
- Blackwell NVENC is a significant step up for Plex transcoding
- TDP is ~180W — same as the 1070 Ti, so the 500W PSU doesn't need upgrading
- Retire the 1070 Ti when this goes in

### LLM upgrade
With 16GB VRAM, switch from Qwen3 8B to **Qwen3-Coder 30B-A3B** in Ollama:
```bash
docker exec -it ollama ollama pull qwen3-coder:30b-a3b
```
The MoE architecture keeps active parameters low enough to fit in 16GB despite the 30B total size. Stronger coding capability while staying in the same Qwen3 family.

### Migration notes
- Reinstall NVIDIA drivers after swap
- Update `hardware.md` with new GPU specs
- Update `llm/README.md` with new model recommendations
