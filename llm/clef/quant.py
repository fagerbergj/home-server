"""Weight-only int4 for Clef on the 3090 (same weights as the reference int4 run) with a torch.compile-fused dequant,
plus per-row int8 embedding tables kept in host RAM (Clef only gathers rows from them)."""
import torch
import torch.nn as nn

G = 128


torch._dynamo.config.cache_size_limit = 64   # one compiled dequant per distinct (N, K) weight shape


def _dequant(packed, scale, n: int, k: int):
    lo, hi = packed & 15, packed >> 4
    q = torch.stack((lo, hi), -1).view(n, -1, G).to(scale.dtype) - 8
    return (q * scale).view(n, -1)[:, :k]


_dequant_fused = torch.compile(_dequant, dynamic=False)   # one Triton kernel per shape; ~0.3 ms for a 5120x17408 weight


class Int4Linear(nn.Module):
    """Group-128 symmetric RTN int4 (absmax/7), two nibbles per byte - bit-identical weights to the reference run's
    scripts/int8.py Int4Linear. The dequant is fused by torch.compile and feeds cuBLAS: on the 3090 this beat PyTorch's
    tinygemm int4 kernel (tuned for decode-size M) at prefill sizes, e.g. 1.6 vs 4.4 ms (M=330) and 5.7 vs 26.7 ms (M=1800)."""

    def __init__(self, lin: nn.Linear, device="cuda"):
        super().__init__()
        w = lin.weight.data.to(device).float()
        n, k = w.shape
        pad = (-k) % G
        if pad: w = torch.nn.functional.pad(w, (0, pad))
        wg = w.view(n, -1, G)
        scale = wg.abs().amax(-1, keepdim=True).clamp(min=1e-8) / 7
        q = (torch.round(wg / scale).clamp(-8, 7) + 8).to(torch.uint8).view(n, -1)
        self.register_buffer("packed", (q[:, 0::2] | (q[:, 1::2] << 4)).contiguous())
        self.register_buffer("scale", scale.to(torch.bfloat16))
        self.bias = None if lin.bias is None else nn.Parameter(lin.bias.data.to(device, torch.bfloat16), requires_grad=False)
        self.in_features, self.out_features = k, n

    def forward(self, x):
        return torch.nn.functional.linear(x, _dequant_fused(self.packed, self.scale, self.out_features, self.in_features).to(x.dtype), self.bias)


def quantize(module: nn.Module, device="cuda", min_features=1024):
    """Replace every large linear with the int4 layer; -> number replaced."""
    n = 0
    for name, child in list(module.named_children()):
        if isinstance(child, nn.Linear) and min(child.in_features, child.out_features) >= min_features:
            setattr(module, name, Int4Linear(child, device)); n += 1
        else:
            n += quantize(child, device, min_features)
    return n


class CpuRowInt8:
    """Per-row int8 table in host RAM (plain attributes, so Module.to() leaves it); rows come back on out_device."""

    def __init__(self, weight: torch.Tensor, out_device="cuda", chunk=8192):
        V, H = weight.shape
        self.q = torch.empty((V, H), dtype=torch.int8)
        self.s = torch.empty((V, 1), dtype=weight.dtype)
        for a in range(0, V, chunk):
            w = weight[a:a + chunk].float()
            s = w.abs().amax(1, keepdim=True).clamp(min=1e-8) / 127
            self.q[a:a + chunk] = torch.round(w / s).to(torch.int8); self.s[a:a + chunk] = s.to(weight.dtype)
        self.out_device = out_device

    def __getitem__(self, ids):
        i = ids.to("cpu") if torch.is_tensor(ids) else ids
        return (self.q[i].to(self.s.dtype) * self.s[i]).to(self.out_device, non_blocking=True)


class CpuEmbedding(nn.Module):
    def __init__(self, table):
        super().__init__(); self.table = table

    def forward(self, ids):
        return self.table[ids]


class CpuHead(nn.Module):
    """lm_head stand-in: Clef's joint head only row-indexes `.weight` for option lexical vectors."""

    def __init__(self, table):
        super().__init__(); self.table = table

    @property
    def weight(self):
        return self.table


def selftest():
    torch.manual_seed(0)
    lin = nn.Linear(1000, 1024, bias=False).to(torch.bfloat16)   # K not a multiple of 128: exercises the padding path
    x = torch.randn(7, 1000, dtype=torch.bfloat16, device="cuda")
    q = Int4Linear(lin)
    eager = torch.nn.functional.linear(x, _dequant(q.packed, q.scale, 1024, 1000))
    assert torch.equal(q(x), eager), "compiled dequant must equal the eager one"
    err = ((q(x).float() - lin.cuda()(x).float()).abs().max() / lin(x).float().abs().max()).item()
    assert err < 0.15, err
    print("int4 ok: compiled == eager dequant; rel err vs bf16", round(err, 4))


if __name__ == "__main__":
    selftest()
