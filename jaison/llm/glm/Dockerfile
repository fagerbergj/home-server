# Scratch: unsloth's glm5next/upstream branch (llama.cpp PR 27754, GLM-5.3-Flash) with upstream DFlash2, HIP gfx1201.
# rdna4-sparse.patch: the branch computes DSA top-k but runs attention dense over every key, and sparse FA is CUDA-only;
# the patch passes the top-k budget, enables the sparse MMA kernel on RDNA4 (512/512 at ncols2 16) and the WMMA indexer.
FROM rocm/dev-ubuntu-24.04:7.2-complete AS build
RUN apt-get update && apt-get install -y --no-install-recommends curl patch cmake ninja-build libcurl4-openssl-dev ca-certificates && rm -rf /var/lib/apt/lists/*
ARG REF=glm5next/upstream
RUN mkdir /src && curl -sSL --retry 10 --retry-all-errors https://github.com/unslothai/llama.cpp/archive/refs/heads/${REF}.tar.gz | tar xz -C /src --strip-components=1
COPY rdna4-sparse.patch /tmp/
RUN cd /src && patch -p1 < /tmp/rdna4-sparse.patch
RUN cd /src && HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" cmake -S . -B build -G Ninja \
      -DGGML_HIP=ON -DAMDGPU_TARGETS=gfx1201 -DGPU_TARGETS=gfx1201 -DCMAKE_BUILD_TYPE=Release \
      -DLLAMA_CURL=ON -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DBUILD_SHARED_LIBS=ON -DGGML_BACKEND_DL=ON -DGGML_CPU_ALL_VARIANTS=ON \
    && cmake --build build --target llama-server -j24
FROM rocm/dev-ubuntu-24.04:7.2-complete
RUN apt-get update && apt-get install -y --no-install-recommends libcurl4 libgomp1 curl && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/build/bin/ /app/
ENV LD_LIBRARY_PATH=/app:/opt/rocm/lib
ENTRYPOINT ["/app/llama-server"]
