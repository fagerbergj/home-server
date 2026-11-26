# LACT (media box 3090)

`lactd` (headless) persists the 3090's fan curve and power cap:

- **Fan floor:** 45 % (the fans need ≥45 % duty to spin; below ~60 °C the vBIOS zero-RPM cycling was audible)
- **Ramp:** 5-point curve to 100 % at 85 °C
- **Damping:** 3 °C hysteresis and 8 s spin-down delay so transcode spikes do not surge the fans
- **Power cap:** 250 W (9B decode -3.5 %, -100 W; 200 W costs -25 %)

Replaced the Xorg/Coolbits fan service and the nvidia-smi power-limit unit.
Restore: `sudo cp media-box-config.yaml /etc/lact/config.yaml && sudo systemctl restart lactd`.
jaison's profile lives in `jaison/lact/`.
