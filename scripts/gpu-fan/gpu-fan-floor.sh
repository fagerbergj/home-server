#!/bin/bash
# Headless 3090 fan floor. Manual fan mode disables the vBIOS curve, so this loop is the curve:
# FLOOR below 55 C, +3 %/C above it. NVIDIA only exposes fan control through X + Coolbits.
set -eu
FLOOR=${1:-45}  # this 3090 needs >=45 % to start its fans
Xorg :99 -config /etc/X11/xorg.conf -noreset >/var/log/gpu-fan-xorg.log 2>&1 &
trap 'kill $! 2>/dev/null' EXIT
for i in $(seq 1 30); do [ -S /tmp/.X11-unix/X99 ] && break; sleep 1; done
export DISPLAY=:99
nvidia-settings -a "[gpu:0]/GPUFanControlState=1" >/dev/null
last=-1
while sleep 5; do
  t=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits)
  s=$(( t > 55 ? FLOOR + (t - 55) * 3 : FLOOR )); [ $s -gt 100 ] && s=100
  [ $s -eq $last ] && continue
  nvidia-settings -a "[fan:0]/GPUTargetFanSpeed=$s" -a "[fan:1]/GPUTargetFanSpeed=$s" >/dev/null && last=$s
done
