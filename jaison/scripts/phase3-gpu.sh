#!/bin/bash
# jaison GPUs: ROCm userspace for monitoring, device groups, and no runtime PM.
# The llama.cpp containers bundle their own userspace; the host needs the
# in-tree amdgpu driver (already in 26.04's kernel), rocm-smi, and the groups.
set -euo pipefail
sudo apt install -y rocm-smi rocminfo vulkan-tools
sudo usermod -aG render,video "$USER"

# An idle R9700 runtime-suspends; a monitoring poll then resumes it every 30 s
# and one failed resume hangs the kernel (media box, 2026-08-29). Keep the cards on.
sudo tee /etc/udev/rules.d/90-amdgpu-no-runtime-pm.rules >/dev/null <<'RULE'
ACTION=="add|bind", SUBSYSTEM=="pci", DRIVER=="amdgpu", ATTR{power/control}="on"
RULE
for d in /sys/bus/pci/drivers/amdgpu/0000:*; do
  echo on | sudo tee "$d/power/control" >/dev/null
done
echo "=== Phase 3 complete: reboot, then check rocm-smi and power/control ==="
