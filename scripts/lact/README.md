# LACT (media box 3090)

`lactd` (headless) persists the 3090's fan curve (45 % floor — the card's fans need ≥45 % duty to spin; below ~60 °C the vBIOS zero-RPM cycling was audible) and the 250 W power cap (9B decode -3.5 %, -100 W; 200 W costs -25 %). Replaced the Xorg/Coolbits fan service and the nvidia-smi power-limit unit. Restore: `sudo cp media-box-config.yaml /etc/lact/config.yaml && sudo systemctl restart lactd`. jaison's profile lives in `jaison/lact/`.
