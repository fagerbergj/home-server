# llama.cpp b11429 (d8123504) + one model's patch series, HIP gfx1201 + RCCL, llama-server only.
# Context is jaison/llm: docker build -f upstream/patched.Dockerfile --build-arg PATCHES=mtp4/patches --build-arg NPATCH=1 .
# NPATCH applies the first N patches of the series (mtp4: 1 = port, 2 = dense). The `test` target runs the CPU-only tests.
ARG BASE=docker.io/rocm/dev-ubuntu-24.04:7.2.1-complete@sha256:3db551c4e1229aac1857ac44fcb6141bb749f41348eb572452f11279153c13c3

FROM ${BASE} AS build
ARG LLAMA_COMMIT=d81235049384534c167caea52b85a694f6103d14
ARG PATCHES
ARG NPATCH=99
ENV CCACHE_DIR=/root/.cache/ccache
RUN apt-get update && apt-get install -y --no-install-recommends curl patch cmake ninja-build ccache libssl-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN mkdir /src && curl -sSL --retry 10 --retry-all-errors https://github.com/ggml-org/llama.cpp/archive/${LLAMA_COMMIT}.tar.gz \
    | tar xz -C /src --strip-components=1
COPY ${PATCHES}/ /patches/
RUN cd /src && for p in $(ls /patches/*.patch | head -n ${NPATCH}); do echo "applying $p"; patch -p1 --forward < "$p" || exit 1; done
# ccache: the series share most of ggml-hip, so later images reuse the FA instances
RUN --mount=type=cache,target=/root/.cache/ccache cd /src && HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" \
    cmake -S . -B build -G Ninja \
      -DGGML_HIP=ON -DGGML_HIP_RCCL=ON -DAMDGPU_TARGETS=gfx1201 -DGPU_TARGETS=gfx1201 -DCMAKE_BUILD_TYPE=Release \
      -DLLAMA_BUILD_TESTS=ON -DLLAMA_BUILD_EXAMPLES=OFF -DBUILD_SHARED_LIBS=ON -DGGML_BACKEND_DL=ON -DGGML_CPU_ALL_VARIANTS=ON \
    && cmake --build build --target llama-server -j24

FROM build AS test
RUN --mount=type=cache,target=/root/.cache/ccache cd /src && cmake --build build -j24 \
      --target test-tokenizer-0 test-llama-archs test-sampling
RUN cd /src/build/bin && ./test-tokenizer-0 /src/models/ggml-vocab-qwen35.gguf && ./test-tokenizer-0 /src/models/ggml-vocab-llama-bpe.gguf \
    && ./test-sampling && ./test-llama-archs -a 'qwen4exp|glm5-next|mimo2'

FROM ${BASE}
ARG LLAMA_COMMIT=d81235049384534c167caea52b85a694f6103d14
ARG PATCH_SHA=none
LABEL org.opencontainers.image.revision=${LLAMA_COMMIT} org.opencontainers.image.version=b11429 llama.patches=${PATCH_SHA}
RUN apt-get update && apt-get install -y --no-install-recommends libgomp1 curl && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/build/bin/ /app/
ENV LD_LIBRARY_PATH=/app:/opt/rocm/lib
ENTRYPOINT ["/app/llama-server"]
