#!/usr/bin/env bash
# --------------------------------------------------------------------
# check-compatibility.sh – memory usage calculator for Ollama models
#
# Flags match Ollama blob page field names — see README.md for full field mapping:
#
#   -f  File size (GiB)                       (required)
#   -q  Quantisation bits (4, 8, 16, 32)      (required)  ← from File Type e.g. Q4_K_M
#   -e  Embedding Length                      (required)
#   -b  Block Count                           (required)
#   -k  Attention Head Count (KV)             (optional, but recommended for GQA models)
#   -d  Key/Value Length (head dim)           (optional, default 128)
#   -c  Context Length                        (optional, default 4096)
#   -t  KV cache type: f16, q8_0, q4_0       (optional, default f16)
#       set OLLAMA_KV_CACHE_TYPE to match
#   -a  Architecture type: transformer, ssm   (optional, default transformer)
#       use ssm for hybrid SSM/attention models (Mamba, nemotron-cascade, etc.)
#       where *.attention.head_count_kv is an array of mixed values or zeros
# --------------------------------------------------------------------

while getopts "f:q:e:b:k:d:c:t:a:" opt; do
  case $opt in
    f) F=$OPTARG ;;
    q) Q=$OPTARG ;;
    e) E=$OPTARG ;;
    b) B=$OPTARG ;;
    k) K=$OPTARG ;;
    d) D=$OPTARG ;;
    c) C=$OPTARG ;;
    t) T=$OPTARG ;;
    a) A=$OPTARG ;;
    *) echo "Usage: $0 -f FILE_SIZE -q QUANT -e EMBEDDING -b BLOCKS [-k KV_HEADS] [-d KV_LEN] [-c CONTEXT] [-t KV_TYPE] [-a ARCH]" >&2; exit 1 ;;
  esac
done

if [ -z "$F" ] || [ -z "$Q" ] || [ -z "$E" ] || [ -z "$B" ]; then
  echo "Missing required arguments." >&2
  echo "Usage: $0 -f FILE_SIZE -q QUANT -e EMBEDDING -b BLOCKS [-k KV_HEADS] [-d KV_LEN] [-c CONTEXT] [-t KV_TYPE] [-a ARCH]" >&2
  exit 1
fi

C=${C:-4096}
D=${D:-128}
K=${K:-0}
T=${T:-f16}
A=${A:-transformer}

case $A in
  transformer) ;;
  ssm) ;;
  *) echo "Unknown architecture '$A'. Use transformer or ssm." >&2; exit 1 ;;
esac

# Bytes per KV cache element based on OLLAMA_KV_CACHE_TYPE
case $T in
  f16)   KV_BYTES=2   ;;
  q8_0)  KV_BYTES=1   ;;
  q4_0)  KV_BYTES=0.5 ;;
  *)     echo "Unknown KV cache type '$T'. Use f16, q8_0, or q4_0." >&2; exit 1 ;;
esac

# GPU overhead varies by quantisation
case $Q in
  4|8)  O_GPU=2 ;;
  16)   O_GPU=3 ;;
  32)   O_GPU=4 ;;
  *)    O_GPU=2 ;;
esac

# Model weights on GPU (-f is already the quantized GGUF file size)
gpu_weights=$F

if [ "$A" = "ssm" ]; then
  # SSM layers have fixed-size recurrent state — KV cache does not grow with context
  kv_cache=0
  kv_note="N/A (SSM architecture — KV cache does not grow with context)"
  gpu_total=$(echo "scale=3; $gpu_weights + $O_GPU" | bc)
else
  # KV cache formula: 2 (K+V) * blocks * context * kv_heads * kv_len * bytes_per_element
  # Fallback (no -k): uses embedding length as proxy — overestimates for GQA models
  if [ "$K" -gt 0 ] 2>/dev/null; then
    kv_cache=$(echo "scale=3; 2 * $B * $C * $K * $D * $KV_BYTES / 1024^3" | bc)
    kv_note="(${K} KV heads x ${D} KV len, ${T})"
  else
    kv_cache=$(echo "scale=3; 2 * $B * $C * $E * $KV_BYTES / 1024^3" | bc)
    kv_note="(embedding length proxy, ${T} — pass -k for accuracy)"
  fi
  gpu_total=$(echo "scale=3; $gpu_weights + $kv_cache + $O_GPU" | bc)
fi

cpu_overhead=1.5

echo "────────────────────────────────────────────────────"
echo "Model parameters"
echo "  File size        : $F GiB"
echo "  Quantisation     : ${Q}-bit"
echo "  Embedding Length : $E"
echo "  Block Count      : $B"
echo "  Context Length   : $C tokens"
echo "────────────────────────────────────────────────────"
echo "Estimated memory usage"
echo "  GPU (VRAM)  : ${gpu_total} GiB"
echo "    * Model weights  : ${gpu_weights} GiB"
echo "    * KV cache       : ${kv_cache} GiB  ${kv_note}"
echo "    * GPU overhead   : ${O_GPU} GiB"
echo "  CPU (RAM)   : ~${cpu_overhead} GiB  (bookkeeping only)"
echo "────────────────────────────────────────────────────"
