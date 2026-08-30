#!/bin/bash
# Headless 3090 fan floor: NVIDIA only exposes fan control through X + Coolbits.
set -eu
SPEED=${1:-25}
Xorg :99 -config /etc/X11/xorg.conf -noreset >/var/log/gpu-fan-xorg.log 2>&1 &
trap 'kill $! 2>/dev/null' EXIT
for i in $(seq 1 30); do [ -S /tmp/.X11-unix/X99 ] && break; sleep 1; done
DISPLAY=:99 nvidia-settings -a "[gpu:0]/GPUFanControlState=1" -a "[fan:0]/GPUTargetFanSpeed=$SPEED" -a "[fan:1]/GPUTargetFanSpeed=$SPEED"
