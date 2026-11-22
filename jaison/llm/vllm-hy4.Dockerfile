# vLLM ROCm nightly (2026-11-21, gfx1201 + PR #68296 Hy4-flash/DFly/Rust-VL) +
# PR #68839 AMD overlay (vllm/models/hy_v4*/amd + rocm_aiter_mla_sparse patch).
FROM vllm/vllm-openai-rocm:nightly

ARG PR68839_SHA=93889130afe2c85c01b4d195150325a8e715d05b
RUN python3 - <<'PY'
import json, os, urllib.request, vllm
from pathlib import Path

sha = os.environ.get("PR68839_SHA", "93889130afe2c85c01b4d195150325a8e715d05b")
vllm_root = Path(vllm.__file__).resolve().parent.parent

api = "https://api.github.com/repos/vllm-project/vllm/pulls/68839/files?per_page=100"
req = urllib.request.Request(api, headers={"User-Agent": "vllm-hy4-build/1"})
files = json.loads(urllib.request.urlopen(req, timeout=60).read())

applied = 0
for f in files:
    fn = f["filename"]
    if not fn.startswith("vllm/"):
        continue
    url = f"https://raw.githubusercontent.com/vllm-project/vllm/{sha}/{fn}"
    dst = vllm_root / fn
    dst.parent.mkdir(parents=True, exist_ok=True)
    data = urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "vllm-hy4-build/1"}), timeout=60).read()
    dst.write_bytes(data)
    applied += 1
    print(f"overlaid {fn} ({len(data)} B)")
assert applied >= 20, f"expected >=20 overlaid files, got {applied}"

# Unlock gfx1201 (RDNA4, native OCP FP8 float8_e4m3fn just like gfx950) past the three
# MI355X-only software guards in PR #68839.
for rel in (
    "vllm/models/hy_v4/dfly_config.py",
    "vllm/models/hy_v4_flash/amd/attention.py",
    "vllm/v1/attention/backends/mla/rocm_aiter_mla_sparse.py",
):
    p = vllm_root / rel
    s = p.read_text()
    assert "from vllm.platforms.rocm import on_gfx950" in s and "if not on_gfx950():" in s, rel
    s = s.replace(
        "from vllm.platforms.rocm import on_gfx950",
        "from vllm.platforms.rocm import on_gfx950, on_gfx1201",
    )
    s = s.replace(
        "if not on_gfx950():",
        "if not (on_gfx950() or on_gfx1201()):",
    )
    p.write_text(s)
    print(f"unlocked gfx1201 in {rel}")

# Allow compressed-tensors pack-quantized (INT4 W4A16 group-128) in DFly's checkpoint allowlist.
dfly_p = vllm_root / "vllm/models/hy_v4/dfly_config.py"
ds = dfly_p.read_text()
old_chk = '    if config.get("quant_method") == "fp8":'
new_chk = (
    '    if config.get("quant_method") == "compressed-tensors" and config.get("format") == "pack-quantized":\n'
    '        return\n'
    '    if config.get("quant_method") == "fp8":'
)
assert old_chk in ds
dfly_p.write_text(ds.replace(old_chk, new_chk, 1))
print("unlocked compressed-tensors pack-quantized in dfly_config.py")
PY
