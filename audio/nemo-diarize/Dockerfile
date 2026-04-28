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

# Pre-install numpy + typing_extensions: the python `sox` package's setup.py
# (pulled in by NeMo's ASR extras) imports both at metadata-gen time, before
# pip has installed the rest of requirements.txt. Upgrade pip itself too —
# the system pip on jammy is old enough to choke on some modern wheels.
RUN pip3 install --no-cache-dir --upgrade pip setuptools wheel \
    && pip3 install --no-cache-dir numpy typing_extensions

COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 8000
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
