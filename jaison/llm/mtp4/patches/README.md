# Qwen3.8-Flash-Next patches on llama.cpp b11429 (d8123504)

Built by `upstream/patched.Dockerfile` with `PATCHES=mtp4/patches`: `NPATCH=1` gives `llama-mtp4:b11429-port`,
`NPATCH=2` gives `llama-mtp4:b11429-dense`. PR 28569 (`-sm tensor` for qwen4exp) is upstream, so it is not carried.

- `0001-qwen4exp-MTP-heads-without-token_embd-output-borrow-...patch` ("port-28243"): the part of PR 28243 that b11429
  lacks. An MTP head without `token_embd`/`output` (unsloth `mtp-*-shared-Q8_0.gguf`) borrows the target's through
  `ctx_other` (llama-context now sets it for qwen4exp drafts that miss either tensor), and draft-mtp counts memory as
  shared only for gemma4-assistant, since `ctx_other` alone no longer implies it. An MTP layer with compress ratio 0
  (the shared head's metadata) gets no indexer cache, so upstream's MTP graph runs it dense; without this, its
  never-consumed k-pool inputs would be set on unallocated tensors. PR 28243's own MTP graph is not ported: b11429's
  graph is the same computation (per-stream hnorm, eh_proj, hc mixers, dense attention when the layer is not QSA).
- `0002-qwen4exp-run-the-MTP-draft-layer-dense-...patch` ("dense-mtp"): the draft context never gets an indexer
  cache, so every head runs its MTP layer dense, the Oct 5 self-contained QSA head included. An A/B arm for the
  "indexer per draft step" hypothesis, not a numerical match for a QSA-trained head past the top-k budget.

Heads: port image + shared head = PR 28243 behaviour (dense); port image + Oct 5 head = upstream (QSA draft);
dense image + either head = dense draft.
