# Use RunPod's official serverless ComfyUI worker as the base. They handle
# the serverless wrapping, handler.py, RunPod SDK, Python deps, CUDA, ComfyUI
# boot — all the infrastructure we kept getting wrong.
#
# All we add on top: the Lightricks LTX-Video custom nodes. Weights are pulled
# at runtime from a mounted Network Volume (no Dockerfile bloat).
# Need ComfyUI >= 0.3.70 for the comfy.ldm.lightricks.av_model module that
# ComfyUI-LTXVideo imports. The 5.5.0 base ships ComfyUI 0.3.64 (too old).
# 5.8.5 is the newest published tag as of June 2026.
# Tag list: https://hub.docker.com/r/runpod/worker-comfyui/tags
FROM runpod/worker-comfyui:5.8.5-base

# Install the official LTX-Video custom nodes from Lightricks (for advanced
# samplers; the base I2V workflow uses ComfyUI core nodes only).
RUN cd /comfyui/custom_nodes \
    && git clone --depth 1 https://github.com/Lightricks/ComfyUI-LTXVideo.git \
    && pip install --no-cache-dir -r ComfyUI-LTXVideo/requirements.txt

# Bake the LTX-Video 0.9.5 2B checkpoint (~4.5 GB) into the image.
# LTX-2 19B was ~22 GB and blew past RunPod's build limits, so we use the
# smaller 2B model which fits comfortably in 24 GB VRAM and the build budget.
RUN pip install --no-cache-dir huggingface_hub hf_transfer
RUN python -c "from huggingface_hub import hf_hub_download; hf_hub_download(repo_id='Lightricks/LTX-Video', filename='ltx-video-2b-v0.9.5.safetensors', local_dir='/comfyui/models/checkpoints', local_dir_use_symlinks=False)"

# LTX checkpoints don't bundle a text encoder — they need T5XXL loaded
# separately via ComfyUI's CLIPLoader(type='ltxv'). Pull the fp8 variant
# (~4.5 GB instead of fp16's 9.5 GB) so we stay under RunPod's build budget.
RUN python -c "from huggingface_hub import hf_hub_download; hf_hub_download(repo_id='comfyanonymous/flux_text_encoders', filename='t5xxl_fp8_e4m3fn.safetensors', local_dir='/comfyui/models/text_encoders', local_dir_use_symlinks=False)"

# Also register /runpod-volume as a secondary checkpoint path so larger models
# (e.g. LTX-2 19B if you later upgrade to a 48GB GPU) can live on the volume.
RUN printf 'ltx-video:\n  base_path: /runpod-volume\n  checkpoints: LTX-Video/\n' \
    > /comfyui/extra_model_paths.yaml

# Nothing else — the base image's CMD already runs ComfyUI + RunPod handler.
