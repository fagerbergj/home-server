# Clef 27B decision server for the 3090 (sm_86): int4 weights with a torch.compile-fused dequant, fla + causal_conv1d
# for the Gated DeltaNet layers, dynamic batching. Weights are mounted read-only from the HF archive, never baked in.
FROM pytorch/pytorch:2.8.0-cuda12.8-cudnn9-devel
ENV TORCH_CUDA_ARCH_LIST=8.6 MAX_JOBS=8 PIP_NO_CACHE_DIR=1 HF_HUB_OFFLINE=1 PYTHONUNBUFFERED=1 \
    TORCHINDUCTOR_CACHE_DIR=/cache/inductor TRITON_CACHE_DIR=/cache/triton PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
RUN pip install "transformers==5.17.0" "tokenizers>=0.23.1,<0.24" safetensors "huggingface-hub>=1.0" \
        "fastapi>=0.115" "uvicorn>=0.30" pillow accelerate "flash-linear-attention==0.5.2" \
 && pip install --no-build-isolation "causal-conv1d==1.5.2" \
 && python -c "import causal_conv1d, fla, transformers, torch; print(torch.__version__, transformers.__version__, fla.__version__)"
WORKDIR /app
COPY clef_server.py quant.py /app/
EXPOSE 8013
ENTRYPOINT ["python", "/app/clef_server.py"]
