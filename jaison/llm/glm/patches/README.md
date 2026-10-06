# GLM-5.3-Flash patches on llama.cpp b11429 (d8123504)

Built by `upstream/patched.Dockerfile` with `PATCHES=glm/patches` into `llama-glm:b11429-p1`. Uses upstream's
`glm5-next` arch name, so it needs the Oct 5 shard-1 snapshot (a38483c8...); the four other shards are unchanged.

- `0001-glm5-next-NextN-MTP-draft-graph-ported-from-PR-27754.patch`: b11429 loads the NextN block but throws
  "NextN graph not implemented yet". This adds `graph_mtp` from the unsloth glm5next/upstream branch (PR 27754,
  d07e71ede): [enorm(e); hnorm(h)] -> eh_proj, attn_norm, one DSA layer, plain residual MoE (no mHC),
  shared_head_norm, LM head. It reuses upstream's `build_dsa_layer`, so the draft gets upstream's k-pool indexer
  and sparse mask. Upstream already sizes the draft memory (NextN layer only) and handles the empty recurrent cache,
  so the branch's memory and `seq_rm` changes are not needed.
- `0002-ggml-cuda-sparse-MLA-flash-attention-and-WMMA-lightn...patch`: `glm/rdna4-sparse.patch` rebased. HIP mask
  compaction (`__ballot`, wave32), `ggml_cuda_fattn_sparse_ok_hip` gate (RDNA4 WMMA, 512/512 or 576/512, GQA % 16,
  K >= max(4096, 2 x n_kv_max)), the (512,512,1,16) sparse MMA instance, the WMMA lightning indexer for 32/64 heads.

Conflicts: b11429 reworked sparse FA (index lists per ncols1 query group plus live counts, a wide ncols1 = 8 variant,
`shall_use_sparse(cc, dst, ncols1, ncols2)`). The five rejected fattn.cu hunks and the `may_use_sparse` hunk were
redone by hand on the new code: compaction runs on HIP for both group widths, but HIP takes sparse only at
ncols1 = 1 (the wide variant is not enabled on RDNA4). The `llama-graph.cpp` hunk (pass n_kv_max) is dropped: b11429's
glm5-next already passes `n_sel` = top_k + kpool - 1 to flash attention. The indexer hunks applied with offsets.
