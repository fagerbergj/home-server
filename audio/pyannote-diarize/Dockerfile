# syntax=docker/dockerfile:1.6
FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    HF_HOME=/root/.cache/huggingface

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip ffmpeg libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Use BuildKit cache mounts for pip — wheels persist between builds, so
# incremental changes to requirements.txt only re-download what actually
# changed instead of the full torch + pyannote tree.
RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install --upgrade pip setuptools wheel

# Pin torch + torchaudio to 2.3.1 (cu121). pyannote.audio 3.3 imports
# torchaudio.AudioMetaData which was removed in torchaudio 2.4+. Installing
# torch first so pip's resolver treats it as fixed when handling pyannote.
RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install \
        torch==2.3.1 torchaudio==2.3.1 \
        --index-url https://download.pytorch.org/whl/cu121

COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install -r requirements.txt

COPY app.py .

EXPOSE 8000
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
