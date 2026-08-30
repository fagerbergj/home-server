#!/bin/bash
# jaison memory tuning: keep mmap'd model pages resident over swap.
set -euo pipefail
echo "vm.swappiness=10" | sudo tee /etc/sysctl.d/90-llm.conf >/dev/null
sudo sysctl -q -p /etc/sysctl.d/90-llm.conf
echo "=== Phase 4 complete ==="
