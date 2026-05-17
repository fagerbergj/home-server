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

# Stage 1b: build FFmpeg 6 from source. pyannote.audio 3.4+ depends on
# torchcodec which dlopens libavcodec.so.60 et al. Ubuntu 22.04 only ships
# FFmpeg 4.4. The savoury1 PPA chain works but pulls a tangled mess of
# transitive deps that fight with the ROCm base; building a minimal FFmpeg 6
# under /opt/ffmpeg6 is reproducible, isolated, and only ~5 min cached.
FROM ubuntu:22.04 AS ffmpeg6-build
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        wget xz-utils ca-certificates build-essential pkg-config yasm nasm \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /build
ARG FFMPEG_VERSION=6.1.2
RUN wget -qO ffmpeg.tar.xz https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz \
    && tar -xf ffmpeg.tar.xz \
    && cd ffmpeg-${FFMPEG_VERSION} \
    && ./configure --prefix=/opt/ffmpeg6 \
        --enable-shared --disable-static \
        --disable-doc --disable-debug \
        --disable-network --disable-everything \
        --enable-protocol=file,pipe \
        --enable-demuxer=wav,mov,matroska,ogg,flac,aac,mp3,webm,avi,mp4 \
        --enable-muxer=wav,mov \
        --enable-decoder=pcm_s16le,pcm_f32le,aac,mp3,flac,vorbis,opus,h264,hevc,vp8,vp9 \
        --enable-encoder=pcm_s16le \
        --enable-filter=aresample,aformat,anull,asetnsamples,atrim,scale \
        --enable-parser=aac,h264,hevc,vp9 \
    && make -j$(nproc) \
    && make install

# Stage 2: runtime
# rocm/pytorch (used in the build stages above) ships a full CUDA-built
# PyTorch we don't use, plus MIOpen kernels for every GPU, build tools,
# and multiple Python envs — ~50 GB of dead weight in the final image.
# rocm/dev-ubuntu-22.04:7.2.3-complete provides the ROCm 7.2.3 userspace
# (hipblas, hip-runtime, hsa-runtime) that whisper.cpp links against,
# without any of that. PyTorch comes from the ROCm wheel below; its wheel
# bundles its own ROCm libs but coexists fine with the SDK's.
FROM rocm/dev-ubuntu-22.04:7.2.3-complete

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    HF_HOME=/root/.cache/huggingface

# python3.10 matches the version the ROCm PyTorch wheels target. libsndfile1
# is for soundfile (used in app.py's _load_audio_dict).
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3.10 python3-pip python3.10-venv \
        libsndfile1 \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/python3.10 /usr/bin/python3 \
    && ln -sf /usr/bin/python3 /usr/local/bin/python3

# Install our self-built FFmpeg 6 (binary + shared libs) under /opt/ffmpeg6.
COPY --from=ffmpeg6-build /opt/ffmpeg6 /opt/ffmpeg6
ENV PATH=/opt/ffmpeg6/bin:${PATH} \
    LD_LIBRARY_PATH=/opt/ffmpeg6/lib:${LD_LIBRARY_PATH}

# Bring the whisper.cpp build tree across — whisper-cli loads its sibling .so
# files from the same tree at runtime.
COPY --from=whisper-build /build/whisper.cpp/build /opt/whisper.cpp/build
ENV LD_LIBRARY_PATH=/opt/whisper.cpp/build/src:/opt/whisper.cpp/build/ggml/src:/opt/whisper.cpp/build/ggml/src/ggml-hip:${LD_LIBRARY_PATH}
RUN ln -s /opt/whisper.cpp/build/bin/whisper-cli /usr/local/bin/whisper-cli

WORKDIR /app

# Install ROCm-built PyTorch from pytorch.org's ROCm wheel index. The wheel
# bundles its own ROCm runtime libs and works fine on top of the ROCm 7.2.3
# userspace from the base image — HIP ABI is backwards-compatible.
# pytorch.org doesn't publish torchcodec for the ROCm index, so we don't
# include it here. pyannote will install the PyPI torchcodec as a dep; that
# wheel was compiled against the CUDA torch ABI and dlopen-fails on our
# ROCm torch ('undefined symbol: torch_from_blob'). app.py works around
# this by always passing pyannote {'waveform': tensor, 'sample_rate': int}
# dicts (the documented fallback per the warning in pyannote/audio/core/io.py),
# which avoids the AudioDecoder code path entirely.
RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install --index-url https://download.pytorch.org/whl/rocm7.2 \
        torch torchaudio torchvision \
 && python3 -c "import torch; assert torch.version.hip, f'still not a ROCm build: {torch.__version__}'; print(f'torch installed: {torch.__version__} hip={torch.version.hip}')"

# Capture the ROCm-built torch/torchaudio/torchvision versions into a pip
# constraints file so pyannote.audio's dep resolution can't accidentally
# replace them with CUDA wheels from PyPI. Read the version from each
# module's __version__ attribute (importlib.metadata can drop the local
# version identifier). The +rocm local id makes the == constraint
# un-satisfiable by PyPI's plain or +cu128 wheels.
RUN python3 - <<'PY' > /tmp/torch-constraints.txt
import importlib
for pkg in ("torch", "torchaudio", "torchvision"):
    try:
        m = importlib.import_module(pkg)
    except ImportError:
        continue
    v = getattr(m, "__version__", None)
    if v:
        print(f"{pkg}=={v}")
PY
RUN echo "=== torch constraints (locked from ROCm install) ===" \
 && cat /tmp/torch-constraints.txt \
 && echo "=== end constraints ===" \
 && test -s /tmp/torch-constraints.txt || { echo "FATAL: empty constraints file"; exit 1; } \
 && grep -q "^torch==.*+rocm" /tmp/torch-constraints.txt || { echo "FATAL: torch constraint has no +rocm local id"; cat /tmp/torch-constraints.txt; exit 1; }

# BuildKit cache mounts persist pip wheels across builds, so requirements
# changes only re-download what actually changed.
RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install --upgrade pip setuptools wheel

COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install --upgrade-strategy only-if-needed \
        -c /tmp/torch-constraints.txt \
        -r requirements.txt

# Verify torch wasn't replaced by a non-ROCm wheel during dep resolution.
# Fails the build immediately if pip ignored our constraints — much better
# than a 30-second-later runtime surprise.
RUN python3 -c "import torch; assert torch.version.hip, f'torch is not a ROCm build after pip install: {torch.__version__} (hip={torch.version.hip}, cuda={torch.version.cuda})'; print(f'torch ok: {torch.__version__} hip={torch.version.hip}')"

COPY app.py .

EXPOSE 8000
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
