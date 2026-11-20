#!/usr/bin/env bash
# bench-hy4.sh — Hy4-flash tok/s bench on jaison: short / medium / long sessions.
#
# Unloads the resident 27B vLLM (frees all four R9700s), loads Hy4-flash with the
# production launcher (run-hy4.sh), measures prefill + decode tok/s through the
# server's streaming /v1/completions (the image ships no llama-bench), then
# restores the 27B. Run from jaison:  bash jaison/llm/bench-hy4.sh
#
# Expect 30-60 min: 168 GB first page-in + bench + vLLM cold restart.
# Session sizes are env-overridable: SHORT_P=512 MED_P=4096 LONG_P=16384 ...
set -euo pipefail

LLM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VLLM="qwen38-27b-vllm"
HY4_PORT="${HY4_PORT:-9991}"
VLLM_PORT="${VLLM_PORT:-9993}"

# session shapes: prompt tokens (approx, server reports exact) x generation tokens
SHORT_P="${SHORT_P:-1024}";  SHORT_N="${SHORT_N:-64}"
MED_P="${MED_P:-8192}";      MED_N="${MED_N:-128}"
LONG_P="${LONG_P:-32768}";   LONG_N="${LONG_N:-256}"

say() { echo; echo "=== $*"; }
die() { echo "FATAL: $*" >&2; exit 1; }

say "0/5 sanity"
docker ps -q --filter "name=^${VLLM}$" | grep -q . || die "$VLLM is not running"
curl -s -m 5 "http://127.0.0.1:${HY4_PORT}/health" 2>/dev/null | grep -q ok && die "hy4 already loaded on :${HY4_PORT}"
rocm-smi --showmeminfo vram >/dev/null 2>&1 || die "rocm-smi unavailable"

RESTORED=0
restore() {
  [ "$RESTORED" = 1 ] && return
  RESTORED=1
  docker stop -t 60 hy4 2>/dev/null || true
  wait 2>/dev/null || true
  sleep 3
  if ! docker ps -q --filter "name=^${VLLM}$" | grep -q .; then
    say "restore: relaunching ${VLLM} via router (cold TP4, a few minutes)"
    curl -s -m 1800 -X POST "http://127.0.0.1:11436/v1/chat/completions" \
      -H 'content-type: application/json' \
      -d "{\"model\":\"qwen3.8-27b\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"max_tokens\":1}" \
      > /dev/null || echo "WARNING: trigger request failed; check the router"
    for i in $(seq 1 240); do
      [ "$(curl -s -o /dev/null -w '%{http_code}' -m 2 "http://127.0.0.1:${VLLM_PORT}/health" 2>/dev/null)" = "200" ] && break
      sleep 5
    done
    if [ "$(curl -s -o /dev/null -w '%{http_code}' -m 2 "http://127.0.0.1:${VLLM_PORT}/health" 2>/dev/null)" = "200" ]; then
      say "restore: 27B healthy on :${VLLM_PORT}"
    else
      echo "WARNING: 27B not healthy after 20 min — check docker logs ${VLLM}"
    fi
  fi
}
trap restore EXIT

say "1/5 stopping ${VLLM} and waiting for VRAM to drain"
docker stop -t 60 "$VLLM"
for i in $(seq 1 60); do
  busy=$(rocm-smi --showmeminfo vram --csv 2>/dev/null | awk -F, 'NR>1 && $3+0>1024 {c++} END {print c+0}')
  [ "${busy:-1}" = "0" ] && break
  sleep 5
done
rocm-smi --showmeminfo vram 2>/dev/null || true

say "2/5 loading Hy4 via production launcher, text-only NO_MM (168 GB page-in; first load takes minutes)"
NAME=hy4 PORT="$HY4_PORT" NO_MM=1 bash "$LLM_DIR/run-hy4.sh" &
HY4_PID=$!
for i in $(seq 1 360); do
  curl -s -m 2 "http://127.0.0.1:${HY4_PORT}/health" 2>/dev/null | grep -q ok && break
  kill -0 "$HY4_PID" 2>/dev/null || die "launcher exited early — /tmp/hy4-last.log; if it is a KV/OOM fit, retry with e.g. CTX=262144 PARALLEL=2 (KV is sized at load)"
  sleep 5
done
say "server up; VRAM at load:"
rocm-smi --showmeminfo vram 2>/dev/null || true
free -g | awk 'NR==2 {print "RAM: " $3 "G used / " $2 "G"}'

bench_size() { # name prompt_tokens gen_tokens
  local name="$1" pt="$2" n="$3"
  say "3/5 ${name}: prompt ~${pt} tok, gen ${n} tok"
  python3 - "$HY4_PORT" "$pt" "$n" <<'PY'
import json, sys, time, urllib.request
port, pt, n = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
text = ("The quick brown fox jumps over the lazy dog. " * pt)[: pt * 5]
payload = json.dumps({"prompt": text, "max_tokens": n, "stream": True,
                      "temperature": 0.9, "top_p": 1.0}).encode()
req = urllib.request.Request(f"http://127.0.0.1:{port}/v1/completions", data=payload,
                             headers={"content-type": "application/json"})
t0, first, toks, ptok, usage = time.time(), None, 0, None, {}
with urllib.request.urlopen(req, timeout=7200) as r:
    for line in r:
        line = line.decode().strip()
        if not line.startswith("data:"):
            continue
        data = line[5:].strip()
        if data == "[DONE]":
            break
        d = json.loads(data)
        if first is None:
            first = time.time()
        if d.get("choices") and d["choices"][0].get("text"):
            toks += 1
        if d.get("usage"):
            usage = d["usage"]
tend = time.time()
ptok = usage.get("prompt_tokens") or pt
gen = usage.get("completion_tokens") or toks
ttfb = first - t0
pp = ptok / ttfb if ttfb > 0 else 0
tg = (gen - 1) / (tend - first) if first and tend > first and gen > 1 else 0
print(f"{name:6s} prompt={ptok:>6} gen={gen:>4}  ttfb={ttfb:7.2f}s  "
      f"prefill={pp:8.1f} tok/s  decode={tg:6.2f} tok/s  wall={tend-t0:8.2f}s")
PY
}

say "4/5 warmup (first forward pass pages in cold KV + weights)"
python3 - "$HY4_PORT" 256 8 <<'PY'
import json, sys, urllib.request
port = sys.argv[1]
payload = json.dumps({"prompt": "Warmup. " * 32, "max_tokens": 8, "stream": False,
                      "temperature": 0.9, "top_p": 1.0}).encode()
req = urllib.request.Request(f"http://127.0.0.1:{port}/v1/completions", data=payload,
                             headers={"content-type": "application/json"})
with urllib.request.urlopen(req, timeout=7200) as r:
    r.read()
print("warmup done")
PY

bench_size short "$SHORT_P" "$SHORT_N"
bench_size medium "$MED_P" "$MED_N"
bench_size long  "$LONG_P"  "$LONG_N"

say "5/5 done — restoring 27B"
exit 0
