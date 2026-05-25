#!/usr/bin/env bash
# One-time: build the tfd-runner image (python + pytest) the provider executes
# generated tests in. Run on jason-server.
set -euo pipefail
cd "$(dirname "$0")"
docker build -t tfd-runner .
echo "tfd-runner image ready"
