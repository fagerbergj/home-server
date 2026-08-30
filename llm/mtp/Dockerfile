# Scratch: llama.cpp with the Qwen3.8-Flash-Next MTP draft head (dzannotti recipe):
# llama.cpp b10612 + PR 27742 tree (unslothai/llama.cpp@bea3b12d) + qwen4exp-mtp-draft-head.patch,
# HIP build for gfx1201. Not for prod; used with -md <MTP sidecar>.
FROM rocm/dev-ubuntu-24.04:7.2-complete AS build
RUN apt-get update && apt-get install -y --no-install-recommends git cmake ninja-build libcurl4-openssl-dev ca-certificates && rm -rf /var/lib/apt/lists/*
RUN git clone https://github.com/unslothai/llama.cpp /src && cd /src && git checkout bea3b12d
COPY qwen4exp-mtp-draft-head.patch /tmp/mtp.patch
RUN cd /src && git apply --check /tmp/mtp.patch && git apply /tmp/mtp.patch
RUN cd /src && HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" cmake -S . -B build -G Ninja \
      -DGGML_HIP=ON -DAMDGPU_TARGETS=gfx1201 -DGPU_TARGETS=gfx1201 -DCMAKE_BUILD_TYPE=Release \
      -DLLAMA_CURL=ON -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DBUILD_SHARED_LIBS=ON -DGGML_BACKEND_DL=ON -DGGML_CPU_ALL_VARIANTS=ON \
    && cmake --build build --target llama-server -j24
FROM rocm/dev-ubuntu-24.04:7.2-complete
RUN apt-get update && apt-get install -y --no-install-recommends libcurl4 libgomp1 curl && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/build/bin/ /app/
ENV LD_LIBRARY_PATH=/app:/opt/rocm/lib
ENTRYPOINT ["/app/llama-server"]
