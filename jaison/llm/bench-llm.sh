#!/usr/bin/env bash
# bench-llm.sh — jaison tok/s bench for ANY model in llm-swap.yaml, by model id.
#
# Loads the target with its production launcher (cmd + env straight from the yaml),
# benches sequential session shapes and an optional concurrent load phase, then
# restores the resident model. Replaces bench-hy4.sh.
#
#   MODEL=hy4-flash                 model id in the yaml (default)
#   RESTORE=qwen3.8-27b             model to reload afterwards (default; API model name)
#   CONC=4                          concurrent sweep: 1, 2, 3, 4 parallel requests (0 = off)
#   CONC_P / CONC_N                 concurrent request shape (default = medium)
#   SKIP_SWAP=1                     target already loaded — bench it, no stop/restore
#   LOAD_TIMEOUT=90                 minutes to wait for a cold load
#   SHORT_P=1024 SHORT_N=64 ...     session shapes (prompt x gen tokens)
#   CTX=262144 PARALLEL=2 MODEL=... env overrides flow through to the launcher
#   --dry                           parse + show the plan, touch nothing
#
# Run from jaison:  bash jaison/llm/bench-llm.sh [model-id]
set -euo pipefail

say() { echo; echo "=== $*"; }
die() { echo "FATAL: $*" >&2; exit 1; }

DRY=0; POS=()
for a in "$@"; do case "$a" in --dry) DRY=1 ;; *) POS+=("$a") ;; esac; done
LLM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${CONFIG:-$LLM_DIR/llm-swap.yaml}"
MODEL="${MODEL:-${POS[0]:-hy4-flash}}"
RESTORE="${RESTORE:-qwen3.8-27b}"
ROUTER_PORT="${ROUTER_PORT:-11436}"
CONC="${CONC:-0}"; CONC_P="${CONC_P:-}"; CONC_N="${CONC_N:-}"
SKIP_SWAP="${SKIP_SWAP:-0}"; LOAD_TIMEOUT="${LOAD_TIMEOUT:-90}"
TEMP="${TEMP:-0.9}"; TOPP="${TOPP:-1.0}"
SHORT_P="${SHORT_P:-1024}";  SHORT_N="${SHORT_N:-64}"
MED_P="${MED_P:-8192}";      MED_N="${MED_N:-128}"
LONG_P="${LONG_P:-32768}";   LONG_N="${LONG_N:-256}"
RES="$(mktemp)"   # TSV rows from each phase; rendered as the final table

# ---- parse the prod config -------------------------------------------------
cfg_get() { # key...  -> prints value (scalar / K=V list / expanded cmd)
  python3 - "$CONFIG" "$MODEL" "$@" <<'PY'
import sys
try:
    import yaml
except ImportError:
    sys.exit("FATAL: python3-yaml missing")
cfg = yaml.safe_load(open(sys.argv[1]))
macros = {k: str(v).strip() for k, v in (cfg.get("macros") or {}).items()}
def expand(s):
    import re
    return re.sub(r"\$\{(\w+)\}", lambda m: macros.get(m.group(1), m.group(0)), str(s))
mid = sys.argv[2]
m = (cfg.get("models") or {}).get(mid)
if m is None:
    sys.exit(f"FATAL: model '{mid}' not in {sys.argv[1]} (ids: {', '.join((cfg.get('models') or {}))})")
groups = cfg.get("groups") or {}
group = next((g for g, gv in groups.items() if mid in (gv.get("members") or [])), "")
env = dict(e.split("=", 1) for e in (m.get("env") or []) if "=" in e)
for k in sys.argv[3:]:
    if k == "id":          print(mid)
    elif k == "port":      print(str(m["proxy"]).rsplit(":", 1)[1])
    elif k == "endpoint":  print(m.get("checkEndpoint") or "/health")
    elif k == "container": print(env.get("NAME", ""))
    elif k == "exclusive": print("1" if (groups.get(group) or {}).get("exclusive") else "0")
    elif k == "group":     print(group)
    elif k == "cmd":       print(expand(m["cmd"]).strip())
    elif k == "cmdstop":   print(expand(m.get("cmdStop") or "").strip())
    elif k == "env":       [print(f"{k2}={v2}") for k2, v2 in env.items()]
PY
}

E_TARGET=()
while IFS= read -r line; do E_TARGET+=("$line"); done < <(cfg_get env)
say "0/5 config: model $MODEL from $CONFIG"
T_PORT=$(cfg_get port); T_EP=$(cfg_get endpoint)
T_NAME=$(cfg_get container); T_EXCL=$(cfg_get exclusive); T_GROUP=$(cfg_get group)
T_CMD=$(cfg_get cmd); T_CMDSTOP=$(cfg_get cmdstop)
[ -n "$T_NAME" ] || die "model '$MODEL' has no NAME in env — cannot stop/restore its container"
[ -n "$T_CMD" ] || die "model '$MODEL' has no cmd"
echo "port=$T_PORT container=$T_NAME exclusive=$T_EXCL group=$T_GROUP"
echo "cmd: $T_CMD"
echo "env: ${E_TARGET[*]:-<none>}"

# other exclusive models: the ones loading $TARGET would evict
OTHER_EXCL=""
if [ "$T_EXCL" = "1" ]; then
  OTHER_EXCL=$(python3 - "$CONFIG" "$MODEL" <<'PY'
import sys, yaml
cfg = yaml.safe_load(open(sys.argv[1]))
mid = sys.argv[2]
groups, models = cfg.get("groups") or {}, cfg.get("models") or {}
skip = {mid}
for gv in groups.values():
    if not gv.get("exclusive"): continue
    for member in gv.get("members") or []:
        if member not in skip:
            env = dict(e.split("=", 1) for e in (models.get(member) or {}).get("env") or [] if "=" in e)
            if env.get("NAME"): print(f"{member}={env['NAME']}")
PY
)
fi
if [ "$DRY" = 1 ]; then
  say "dry run — plan:"
  echo "  stop (exclusive peers): ${OTHER_EXCL:-<none>}"
  echo "  load: $T_CMD (env: ${E_TARGET[*]:-<none>})"
  echo "  bench: short ${SHORT_P}/${SHORT_N}, medium ${MED_P}/${MED_N}, long ${LONG_P}/${LONG_N}"
  [ "$CONC" -gt 0 ] && echo "  concurrent: sweep 1..$CONC x ${CONC_P:-$MED_P}/${CONC_N:-$MED_N}"
  echo "  restore: $RESTORE"
  exit 0
fi

RESTORED=0; LOADED=0
restore() {
  [ "$RESTORED" = 1 ] && return
  RESTORED=1
  rm -f "$RES"
  if [ "$LOADED" = "1" ]; then
    say "restore: stopping $T_NAME"
    bash -c "$T_CMDSTOP" 2>/dev/null || true
    sleep 3
  fi
  local rport; rport=$(cfg_get "$RESTORE" port 2>/dev/null) || { echo "WARNING: $RESTORE not in $CONFIG — cannot verify restore"; return; }
  # is the restore model already up?
  if [ -n "$rport" ] && [ "$(curl -s -o /dev/null -w '%{http_code}' -m 2 "http://127.0.0.1:${rport}$(cfg_get "$RESTORE" endpoint 2>/dev/null || echo /health)" 2>/dev/null)" = "200" ]; then
    say "restore: $RESTORE already healthy"
    return
  fi
  say "restore: relaunching $RESTORE via router (cold load, a few minutes)"
  curl -s -m 1800 -X POST "http://127.0.0.1:${ROUTER_PORT}/v1/chat/completions" \
    -H 'content-type: application/json' \
    -d "{\"model\":\"$RESTORE\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"max_tokens\":1}" \
    > /dev/null || echo "WARNING: trigger request failed; check the router"
  for i in $(seq 1 240); do
    [ "$(curl -s -o /dev/null -w '%{http_code}' -m 2 "http://127.0.0.1:${rport}/health" 2>/dev/null)" = "200" ] && break
    sleep 5
  done
  if [ "$(curl -s -o /dev/null -w '%{http_code}' -m 2 "http://127.0.0.1:${rport}/health" 2>/dev/null)" = "200" ]; then
    say "restore: $RESTORE healthy on :${rport}"
  else
    echo "WARNING: $RESTORE not healthy after 20 min — check the router"
  fi
}
trap restore EXIT

# ---- stop peers, load target ------------------------------------------------
STOPS=()
if [ "$SKIP_SWAP" = "1" ]; then
  say "1/5 SKIP_SWAP: benching $MODEL as-is"
elif [ "$T_EXCL" = "1" ] && [ -n "$OTHER_EXCL" ]; then
  while IFS='=' read -r mname cname; do
    [ -n "$cname" ] || continue
    docker ps -q --filter "name=^${cname}$" | grep -q . && STOPS+=("$cname")
  done <<< "$OTHER_EXCL"
  if [ "${#STOPS[@]}" = "0" ]; then
    say "1/5 no exclusive peer loaded"
  else
    say "1/5 stopping: ${STOPS[*]}"
    for c in "${STOPS[@]}"; do docker stop -t 60 "$c"; done
    drained=0
    for i in $(seq 1 60); do
      # driver baseline is ~60 MB; require < 1 GB per card
      busy=$(rocm-smi --showmeminfo vram --csv 2>/dev/null | awk -F, 'NR>1 && $3+0>1073741824 {c++} END {print c+0}')
      [ "${busy:-1}" = "0" ] && { drained=1; break; }
      sleep 5
    done
    [ "$drained" = "1" ] || die "VRAM did not drain after stopping ${STOPS[*]} — check rocm-smi"
    rocm-smi --showmeminfo vram 2>/dev/null || true
  fi
else
  say "1/5 not exclusive; stopping nothing"
fi

if [ "$(curl -s -o /dev/null -w '%{http_code}' -m 2 "http://127.0.0.1:${T_PORT}${T_EP}" 2>/dev/null)" = "200" ]; then
  say "2/5 $MODEL already healthy on :$T_PORT — benching it (no load)"
else
  docker ps -q --filter "name=^${T_NAME}$" | grep -q . && die "container $T_NAME exists but is not healthy — docker stop $T_NAME first"
  say "2/5 loading $MODEL via production launcher: $T_CMD"
  # launcher env from the yaml + this environment (so CTX=/PARALLEL=/TENSOR_SPLIT= flow through)
  env "${E_TARGET[@]}" bash -c "$T_CMD" &
  T_PID=$!
  for i in $(seq 1 $((LOAD_TIMEOUT * 12))); do
    [ "$(curl -s -o /dev/null -w '%{http_code}' -m 2 "http://127.0.0.1:${T_PORT}${T_EP}" 2>/dev/null)" = "200" ] && { LOADED=1; break; }
    kill -0 "$T_PID" 2>/dev/null || die "launcher exited early — check its log; if it is a KV/OOM fit, retry with e.g. CTX=262144 PARALLEL=2 $MODEL"
    sleep 5
  done
  [ "$LOADED" = "1" ] || die "$MODEL not healthy after ${LOAD_TIMEOUT} min"
fi
say "server up; VRAM at load:"
rocm-smi --showmeminfo vram 2>/dev/null || true
free -g | awk 'NR==2 {print "RAM: " $3 "G used / " $2 "G"}'

# ---- bench -------------------------------------------------------------------
bench_size() { # name prompt_tokens gen_tokens
  local name="$1" pt="$2" n="$3"
  say "3/5 ${name}: prompt ~${pt} tok, gen ${n} tok"
  python3 - "$name" "$T_PORT" "$pt" "$n" "$TEMP" "$TOPP" "$RES" <<'PY'
import json, sys, time, urllib.request
name, port, pt, n, temp, topp = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4], float(sys.argv[5]), float(sys.argv[6])
# distinct prefix per session: identical prefixes make llama.cpp reuse the previous
text = ((f"{name} session filler. " + "The quick brown fox jumps over the lazy dog. ") * pt)[: pt * 5]
payload = json.dumps({"prompt": text, "max_tokens": n, "stream": True,
                      "temperature": temp, "top_p": topp}).encode()
req = urllib.request.Request(f"http://127.0.0.1:{port}/v1/completions", data=payload,
                             headers={"content-type": "application/json"})
t0, first, toks, usage = time.time(), None, 0, {}
with urllib.request.urlopen(req, timeout=7200) as r:
    for line in r:
        line = line.decode().strip()
        if not line.startswith("data:"): continue
        data = line[5:].strip()
        if data == "[DONE]": break
        d = json.loads(data)
        if first is None: first = time.time()
        if d.get("choices") and (d["choices"][0].get("text") or d["choices"][0].get("reasoning")): toks += 1
        if d.get("usage"): usage = d["usage"]
tend = time.time()
ptok = usage.get("prompt_tokens") or pt
gen = usage.get("completion_tokens") or toks
ttfb = first - t0
pp = ptok / ttfb if ttfb > 0 else 0
tg = (gen - 1) / (tend - first) if first and tend > first and gen > 1 else 0
with open(sys.argv[7], "a") as f:
    f.write(f"seq\t{name}\t{ptok}\t{gen}\t{ttfb:.3f}\t{pp:.3f}\t{tg:.3f}\t{tend - t0:.3f}\n")
PY
}

bench_conc() { # maxN prompt_tokens gen_tokens — sweeps 1..maxN parallel, one summary line per level
  local maxn="$1" pt="$2" n="$3"
  say "3/5 concurrent sweep: 1..$maxn parallel x prompt ~${pt} tok, gen ${n} tok"
  local lvl
  for lvl in $(seq 1 "$maxn"); do
    python3 - "$lvl" "$T_PORT" "$pt" "$n" "$TEMP" "$TOPP" "$RES" <<'PY'
import json, sys, time, threading, urllib.request
nn, port, pt, n, temp, topp = int(sys.argv[1]), sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), float(sys.argv[5]), float(sys.argv[6])
def work(i, go):
    text = ((f"concurrent worker {i} filler. " + "The quick brown fox jumps over the lazy dog. ") * pt)[: pt * 5]
    payload = json.dumps({"prompt": text, "max_tokens": n, "stream": True,
                          "temperature": temp, "top_p": topp}).encode()
    req = urllib.request.Request(f"http://127.0.0.1:{port}/v1/completions", data=payload,
                                 headers={"content-type": "application/json"})
    t0 = time.time(); go.wait()
    first, toks, usage = None, 0, {}
    with urllib.request.urlopen(req, timeout=7200) as r:
        for line in r:
            line = line.decode().strip()
            if not line.startswith("data:"): continue
            data = line[5:].strip()
            if data == "[DONE]": break
            d = json.loads(data)
            if first is None: first = time.time()
            if d.get("choices") and (d["choices"][0].get("text") or d["choices"][0].get("reasoning")): toks += 1
            if d.get("usage"): usage = d["usage"]
    tend = time.time()
    gen = usage.get("completion_tokens") or toks
    return (usage.get("prompt_tokens") or pt, (first - t0) if first else 0, tend - t0, gen)
go = threading.Event(); res = [None] * nn
def runner(i): res[i] = work(i, go)
ts = [threading.Thread(target=runner, args=(i,)) for i in range(nn)]
[t.start() for t in ts]
time.sleep(1.5)   # let the requests build up, then release them together
go.set()
[t.join() for t in ts]
tot_gen = sum(r[3] for r in res); wall = max(r[2] for r in res)
ttfbs = sorted(r[1] for r in res)
agg = tot_gen / wall
with open(sys.argv[7], "a") as f:
    f.write(f"conc\t{nn}\t{res[0][0]}\t{tot_gen}\t{wall:.3f}\t{agg:.3f}\t{agg / nn:.3f}\t"
            f"{ttfbs[0]:.3f}\t{ttfbs[len(ttfbs) // 2]:.3f}\t{ttfbs[-1]:.3f}\n")
PY
    sleep 2   # let slots release between levels
  done
}

print_table() { # model_id port
  say "results: $1 (:$2)"
  python3 - "$RES" "$1" "$2" <<'PY'
import sys
rows = [l.rstrip("\n").split("\t") for l in open(sys.argv[1]) if l.strip()]
seq = [r for r in rows if r[0] == "seq"]
con = [r for r in rows if r[0] == "conc"]
if seq:
    print("\nsequential (one request at a time)")
    print(f"  {'shape':7s} {'prompt':>7s} {'gen':>5s} {'ttfb':>9s} {'prefill':>10s} {'decode':>10s} {'wall':>9s}")
    for r in seq:
        print(f"  {r[1]:7s} {r[2]:>7s} {r[3]:>5s} {float(r[4]):8.2f}s {float(r[5]):>9.1f}/s {float(r[6]):>9.2f}/s {float(r[7]):8.2f}s")
if con:
    print(f"\nconcurrent sweep (prompt ~{con[0][2]} x gen, all requests released together)")
    print(f"  {'parallel':>8s} {'wall':>9s} {'aggregate':>11s} {'per-stream':>11s} {'ttfb min/med/max (s)':>24s}")
    for r in con:
        print(f"  {r[1]:>8s} {float(r[4]):8.2f}s {float(r[5]):>10.1f}/s {float(r[6]):>10.2f}/s "
              f"{float(r[7]):6.2f}/{float(r[8]):6.2f}/{float(r[9]):6.2f}")
PY
}

say "4/5 warmup (first forward pass pages in cold KV + weights)"
python3 - "$T_PORT" "$TEMP" "$TOPP" <<'PY'
import json, sys, urllib.request
port, temp, topp = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
payload = json.dumps({"prompt": "Warmup. " * 32, "max_tokens": 8, "stream": False,
                      "temperature": temp, "top_p": topp}).encode()
req = urllib.request.Request(f"http://127.0.0.1:{port}/v1/completions", data=payload,
                             headers={"content-type": "application/json"})
with urllib.request.urlopen(req, timeout=7200) as r:
    r.read()
print("warmup done")
PY

bench_size short "$SHORT_P" "$SHORT_N"
bench_size medium "$MED_P" "$MED_N"
bench_size long  "$LONG_P"  "$LONG_N"
[ "$CONC" -gt 0 ] && bench_conc "$CONC" "${CONC_P:-$MED_P}" "${CONC_N:-$MED_N}"

print_table "$MODEL" "$T_PORT"

say "done — restoring"
exit 0
