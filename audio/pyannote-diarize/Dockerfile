# syntax=docker/dockerfile:1.6

# Stage 1: build whisper.cpp with HIPBLAS for AMD GPU acceleration on RDNA 4.
# AMDGPU_TARGETS=gfx1201 = R9700 (Navi 48). Update if the GPU ever changes.
FROM rocm/pytorch:rocm7.2.3_ubuntu22.04_py3.10_pytorch_release_2.10.0 AS whisper-build

RUN apt-get update && apt-get install -y --no-install-recommends \
        git cmake build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN git clone --depth=1 https://github.com/ggml-org/whisper.cpp.git
WORKDIR /build/whisper.cpp
RUN cmake -B build -DGGML_HIP=ON -DAMDGPU_TARGETS=gfx1201 -DCMAKE_BUILD_TYPE=Release \
    && cmake --build build -j --config Release

# Stage 2: runtime
FROM rocm/pytorch:rocm7.2.3_ubuntu22.04_py3.10_pytorch_release_2.10.0

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    HF_HOME=/root/.cache/huggingface

# FFmpeg 6 — pyannote.audio 3.4+ depends on torchcodec which needs FFmpeg 6
# shared libs (libavcodec.so.60, libavformat.so.60, libavutil.so.58).
# Ubuntu 22.04 ships FFmpeg 4.4, so pull FFmpeg 6 from savoury1's PPA.
# The ffmpeg4 PPA must be added alongside ffmpeg6 — it provides ancillary
# libs (libsndio7, etc.) that the ffmpeg6 packages depend on but doesn't
# itself include. Documented in savoury1/ffmpeg6 PPA notes.
RUN apt-get update && apt-get install -y --no-install-recommends \
        software-properties-common \
    && add-apt-repository -y ppa:savoury1/ffmpeg4 \
    && add-apt-repository -y ppa:savoury1/ffmpeg6 \
    && apt-get update && apt-get install -y --no-install-recommends \
        ffmpeg libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

# Bring the whisper.cpp build tree across — whisper-cli loads its sibling .so
# files from the same tree at runtime.
COPY --from=whisper-build /build/whisper.cpp/build /opt/whisper.cpp/build
ENV LD_LIBRARY_PATH=/opt/whisper.cpp/build/src:/opt/whisper.cpp/build/ggml/src:/opt/whisper.cpp/build/ggml/src/ggml-hip:${LD_LIBRARY_PATH}
RUN ln -s /opt/whisper.cpp/build/bin/whisper-cli /usr/local/bin/whisper-cli

WORKDIR /app

# Capture the base image's pre-installed ROCm-built torch/torchaudio/torchvision
# versions into a pip constraints file. Without this, pip resolving
# pyannote.audio's deps will silently replace those wheels with CUDA-only ones
# from PyPI — manifests as "no NVIDIA driver" at the first .to("cuda") call.
# The constraint pins force pip to leave the ROCm wheels alone.
RUN pip3 freeze 2>/dev/null \
    | grep -iE "^(torch|torchaudio|torchvision|pytorch-triton-rocm)==" \
    > /tmp/torch-constraints.txt \
 && echo "=== torch constraints (locked from base image) ===" \
 && cat /tmp/torch-constraints.txt

# BuildKit cache mounts persist pip wheels across builds, so requirements
# changes only re-download what actually changed.
RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install --upgrade pip setuptools wheel

COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install -c /tmp/torch-constraints.txt -r requirements.txt

COPY app.py .

EXPOSE 8000
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
