# RunPod Serverless worker for Faceless Studio — ComfyUI + LTX-Video 2.3.
#
# Build size is roughly 28 GB once LTX weights are baked in. RunPod's GitHub
# build pipeline handles this on their infrastructure so you don't pay for it.
# Cold start ~30-45 seconds; subsequent runs on the same worker are ~5 seconds.
#
# Substitution placeholders in the LTX workflow JSON (filled by server.js):
#   {{PROMPT}}, {{KEYFRAME_B64}}, {{FRAMES}}, {{WIDTH}}, {{HEIGHT}}, {{SEED}}

FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    HF_HUB_ENABLE_HF_TRANSFER=1

# System deps. ffmpeg/libsndfile for ComfyUI's video nodes; git for ComfyUI install.
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip python3-venv \
        git wget ffmpeg libsndfile1 libgl1 libglib2.0-0 \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN ln -sf /usr/bin/python3 /usr/bin/python && python -m pip install --upgrade pip

WORKDIR /opt

# --- ComfyUI ---------------------------------------------------------------
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI
WORKDIR /opt/ComfyUI
RUN pip install -r requirements.txt

# Torch + CUDA 12.1 wheels (ComfyUI requirements installs a CPU torch otherwise)
RUN pip install --extra-index-url https://download.pytorch.org/whl/cu121 \
        torch==2.4.0 torchvision==0.19.0 torchaudio==2.4.0

# --- LTX-Video custom nodes ------------------------------------------------
WORKDIR /opt/ComfyUI/custom_nodes
RUN git clone --depth 1 https://github.com/Lightricks/ComfyUI-LTXVideo.git \
    && pip install -r ComfyUI-LTXVideo/requirements.txt || true

# --- huggingface_hub for runtime LTX download -----------------------------
# We do NOT bake the LTX weights into the image — they're ~22 GB and blow past
# RunPod's build-time disk/timeout limits. start.sh downloads them on first
# cold start. If a Network Volume is mounted at /runpod-volume, weights persist
# across worker spawns. Otherwise each new worker downloads (~2-4 min).
RUN pip install --no-cache-dir huggingface_hub hf_transfer

# --- RunPod worker ---------------------------------------------------------
WORKDIR /workspace
COPY requirements.txt /workspace/requirements.txt
RUN pip install -r /workspace/requirements.txt

COPY handler.py /workspace/handler.py
COPY start.sh /workspace/start.sh
RUN chmod +x /workspace/start.sh

EXPOSE 8188

CMD ["/workspace/start.sh"]
