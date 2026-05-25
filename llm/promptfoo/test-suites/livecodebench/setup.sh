#!/usr/bin/env bash
# One-time (re)build of the LiveCodeBench runtime the provider depends on:
#   - clones LiveCodeBench into $LCB_HOME/LiveCodeBench
#   - builds a Python 3.10 venv at $LCB_HOME/venv with MINIMAL deps (NO vllm/torch)
#   - materializes a PINNED problem set into $LCB_HOME/problems.json
#
# Everything runs in a python:3.10-slim container mounting $LCB_HOME at /work.
# The venv is path-pinned to /work, so the provider must also mount there.
# Python 3.10 (not 3.11+) because pyext needs inspect.getargspec; datasets==3.2.0
# because 4.x dropped loading-script support and LCB ships one.
#
# Pin the comparison set (contamination control — choose a window past the
# training cutoffs of the models you compare):
#   LCB_RELEASE=release_v6 LCB_START=2025-01-01 LCB_END=2025-04-30 \
#   LCB_N=50 HF_TOKEN=... ./setup.sh
set -euo pipefail

LCB_HOME="${LCB_HOME:-$HOME/lcb-smoke}"
SCRIPTS="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$LCB_HOME"
[ -d "$LCB_HOME/LiveCodeBench" ] \
  || git clone --depth 1 https://github.com/LiveCodeBench/LiveCodeBench "$LCB_HOME/LiveCodeBench"

docker run --rm --network host \
  -v "$LCB_HOME:/work" -v "$SCRIPTS:/scripts" \
  -e "LCB_RELEASE=${LCB_RELEASE:-release_v6}" \
  -e "LCB_START=${LCB_START:-}" -e "LCB_END=${LCB_END:-}" -e "LCB_N=${LCB_N:-0}" \
  -e "HF_TOKEN=${HF_TOKEN:-}" -e "HF_HOME=/work/hf" \
  python:3.10-slim bash -c '
    set -e
    pip install -q uv
    [ -d /work/venv ] || uv venv /work/venv
    . /work/venv/bin/activate
    uv pip install -q "datasets==3.2.0" numpy tqdm requests pyext
    PYTHONPATH=/work/LiveCodeBench LCB_OUT=/work/problems.json python /scripts/fetch_problems.py
  '

echo "LCB runtime ready at $LCB_HOME  (problems.json materialized)"
