FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    HF_HOME=/root/.cache/huggingface \
    NEMO_CACHE_DIR=/root/.cache/nemo

# sox + libsox-fmt-all: needed at build time by the python `sox` package
# (NeMo ASR extras) and at runtime for audio decoding.
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip ffmpeg sox libsox-fmt-all libsndfile1 git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Pre-install numpy so the python `sox` package's setup.py (which imports
# numpy at metadata generation time) can build. NeMo will resolve a compatible
# torch >= 2.6 against CUDA 12.1 on its own.
RUN pip3 install --no-cache-dir numpy

COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 8000
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
