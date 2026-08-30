# LACT (GPU tuning on jaison)

`lactd` (headless deb) applies this at boot: fan curve (35→35 %, 95→100 %, keyed on edge temp), `max_memory_clock: 1359`, `voltage_offset: -125` on both R9700s. Requires `amdgpu.ppfeaturemask=0xffffffff` on the kernel cmdline (set in /etc/default/grub).

Why: stock fan curve let card 0's GDDR6 reach 96 C and thermally derate mid-decode (runs dropped to ~40 t/s); the curve + undervolt hold VRAM ≤86 C under sustained dual-stream decode. The mclk bump is within noise for vLLM decode (measured 2026-08-30); -150 mV also passed but -125 keeps margin. Restore: `sudo cp config.yaml /etc/lact/ && sudo systemctl restart lactd`.
