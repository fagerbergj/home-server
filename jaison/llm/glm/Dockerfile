# Scratch: upstream llama.cpp master + PR 27754 (GLM-5-Next / GLM-5.3-Flash), HIP gfx1201.
FROM rocm/dev-ubuntu-24.04:7.2-complete AS build
RUN apt-get update && apt-get install -y --no-install-recommends git cmake ninja-build libcurl4-openssl-dev ca-certificates && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 50 https://github.com/ggml-org/llama.cpp /src
COPY glm5-next.patch /tmp/glm.patch
RUN cd /src && git apply --3way /tmp/glm.patch
RUN cd /src && HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" cmake -S . -B build -G Ninja \
      -DGGML_HIP=ON -DAMDGPU_TARGETS=gfx1201 -DGPU_TARGETS=gfx1201 -DCMAKE_BUILD_TYPE=Release \
      -DLLAMA_CURL=ON -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DBUILD_SHARED_LIBS=ON -DGGML_BACKEND_DL=ON -DGGML_CPU_ALL_VARIANTS=ON \
    && cmake --build build --target llama-server -j24
FROM rocm/dev-ubuntu-24.04:7.2-complete
RUN apt-get update && apt-get install -y --no-install-recommends libcurl4 libgomp1 curl && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/build/bin/ /app/
ENV LD_LIBRARY_PATH=/app:/opt/rocm/lib
ENTRYPOINT ["/app/llama-server"]
