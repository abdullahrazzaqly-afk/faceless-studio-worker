# Use RunPod's official serverless ComfyUI worker as the base. They handle
# the serverless wrapping, handler.py, RunPod SDK, Python deps, CUDA, ComfyUI
# boot — all the infrastructure we kept getting wrong.
#
# All we add on top: the Lightricks LTX-Video custom nodes. Weights are pulled
# at runtime from a mounted Network Volume (no Dockerfile bloat).
FROM runpod/worker-comfyui:5.5.0-base

# Install the official LTX-Video custom nodes from Lightricks.
RUN cd /comfyui/custom_nodes \
    && git clone --depth 1 https://github.com/Lightricks/ComfyUI-LTXVideo.git \
    && pip install --no-cache-dir -r ComfyUI-LTXVideo/requirements.txt

# Allow the running worker to discover models under the mounted Network Volume.
# `extra_model_paths.yaml` is ComfyUI's standard way to register extra dirs.
RUN printf 'ltx-video:\n  base_path: /runpod-volume\n  checkpoints: LTX-Video/\n' \
    > /comfyui/extra_model_paths.yaml

# Nothing else — the base image's CMD already runs ComfyUI + RunPod handler.
