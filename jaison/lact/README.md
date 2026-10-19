# LACT (GPU tuning on jaison)

`lactd` (headless deb) applies this at boot to all four R9700s: stock clocks, stock/auto fan control and a 250 W power cap, identical on every card (no overdrive writes). If sustained decode derates again (VRAM ≥95 C, throughput collapse), re-enable a fan curve; see git history. Requires `amdgpu.ppfeaturemask=0xffffffff` on the kernel cmdline (set in /etc/default/grub).

Why: stock fan curve let card 0's GDDR6 reach 96 C and thermally derate mid-decode (runs dropped to ~40 t/s); the curve + undervolt hold VRAM ≤86 C under sustained dual-stream decode. The mclk bump is within noise for vLLM decode (measured 2026-08-30); -125 mV passed benches but produced 4 mode1 GPU resets over 14 h of sustained eval load (both cards); -150 hung in minutes. 2026-09-03: undervolt removed entirely, 250 W power cap instead (decode unaffected, prefill -13%); suspicion that UV caused silent corruption/reasoning loops. Stock clocks + cap = the boring-stable config. Restore: `sudo cp config.yaml /etc/lact/ && sudo systemctl restart lactd`.

`23:00.0` has wedged nine times since 2026-09-08 (MES `INVALIDATE_TLBS` timeouts, sdma0 ring reset, sometimes "device lost from bus"), at idle and under load alike; `c3:00.0` once (2026-10-19), `03:00.0` once, `c6:00.0` never. A hung SMU survives a warm reboot: power-cycle.
