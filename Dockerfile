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

# --- LTX-2.3 weights -------------------------------------------------------
# Pulls the 22B image-to-video checkpoint from the official Lightricks HF repo.
# Replace this URL when Lightricks ships a newer point release.
RUN pip install --no-cache-dir huggingface_hub hf_transfer
RUN python -c "from huggingface_hub import hf_hub_download; \
    hf_hub_download(repo_id='Lightricks/LTX-Video', filename='ltxv-2.3-22b-i2v.safetensors', \
                    local_dir='/opt/ComfyUI/models/checkpoints', local_dir_use_symlinks=False)"

# Text encoder (T5) — required by LTX nodes for prompt conditioning.
RUN python -c "from huggingface_hub import snapshot_download; \
    snapshot_download(repo_id='google/flan-t5-xxl', local_dir='/opt/ComfyUI/models/text_encoders/t5xxl', \
                      local_dir_use_symlinks=False, allow_patterns=['*.json','*.safetensors','*.model','*.txt'])"

# --- RunPod worker ---------------------------------------------------------
WORKDIR /workspace
COPY requirements.txt /workspace/requirements.txt
RUN pip install -r /workspace/requirements.txt

COPY handler.py /workspace/handler.py
COPY start.sh /workspace/start.sh
RUN chmod +x /workspace/start.sh

EXPOSE 8188

CMD ["/workspace/start.sh"]
