# GLM-5.3-Flash patches on llama.cpp b11580 (4413a192)

Built by `upstream/patched.Dockerfile` with `PATCHES=glm/patches` into `llama-glm:b11580-p1` (`make glm-image`). Uses
upstream's `glm5-next` arch name, so it needs the Oct 5 shard-1 snapshot (a38483c8...); the four other shards are unchanged.
GLM's NextN MTP graph is upstream since #29928, so the port of PR 27754's `graph_mtp` is no longer carried.

- `0001-ggml-cuda-sparse-MLA-flash-attention-and-WMMA-lightn...patch`: HIP mask compaction (`__ballot`, wave32),
  `ggml_cuda_fattn_sparse_ok_hip` gate (RDNA4 WMMA, 512/512 or 576/512, GQA % 16, K >= max(4096, 2 x n_kv_max)), the
  (512,512,1,16) sparse MMA instance, the WMMA lightning indexer for 32/64 heads. Upstream sparse FA still aborts on
  HIP; drop this once draft PR #30370 ("ggml-cuda: Add HIP sparse fattn") lands and benchmarks at least as fast.

Rebase history: b11429 reworked sparse FA (index lists per ncols1 query group plus live counts, a wide ncols1 = 8
variant, `shall_use_sparse(cc, dst, ncols1, ncols2)`); the fattn.cu hunks were redone by hand there. Compaction runs on
HIP for both group widths, but HIP takes sparse only at ncols1 = 1 (the wide variant is not enabled on RDNA4).
glm5-next already passes `n_sel` = top_k + kpool - 1 to flash attention. Applies to b11580 unchanged.
