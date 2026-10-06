# MiMo patches on llama.cpp b11429 (d8123504)

Built by `upstream/patched.Dockerfile` with `PATCHES=mimo/patches` into `llama-mimo:b11429-p1`.

- `0001-dflash-use-the-target-s-lm_head-...patch`: a DFlash draft with no `output` tensor now always uses the target's
  lm_head through `ctx_other`. b11429 tied such a draft's head to its own `token_embd`, but the TrevorJS
  MiMo-V2.6-Flash-RL drafter ships a `token_embd` that matches neither the target's `token_embd` nor its `output`
  (checked by tensor hash). A draft that ships `output` keeps it. Origin: the tie removal in `mimo/mimo2-dflash.patch`.

The rest of `mimo2-dflash.patch` (mimo2 layer-input hooks, the final-residual crop, DFlash `value_scale`) is upstream
since #29650, so it is not carried. Side effect: a Gemma4 DSpark draft without `output` now reads the tied target's
head instead of its own copy of the same embedding, which costs nothing unless the draft runs on other devices (`-devd`).
