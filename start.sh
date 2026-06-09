#!/bin/bash
# Download LTX-Video weights on cold start (if not already cached),
# boot ComfyUI in the background, then hand control to the RunPod handler.

set -e

# If RunPod mounted a Network Volume at /runpod-volume, persist weights there
# so they survive worker scaledown. Otherwise fall back to local container
# storage (downloads every cold start, which is suboptimal but works).
if [ -d "/runpod-volume" ]; then
    MODEL_ROOT="/runpod-volume"
    echo "→ Using mounted Network Volume at /runpod-volume for model cache"
else
    MODEL_ROOT="/opt/ComfyUI/models/checkpoints"
    echo "→ No Network Volume mounted — caching to container-local storage (will redownload on next cold start)"
fi

LTX_DIR="$MODEL_ROOT/LTX-Video"
mkdir -p "$LTX_DIR"

# Skip download if weights are already there (any .safetensors file present).
if compgen -G "$LTX_DIR/*.safetensors" > /dev/null; then
    echo "→ LTX weights already present in $LTX_DIR, skipping download"
else
    echo "→ Downloading LTX-Video weights (~22 GB, one-time)..."
    python -c "
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id='Lightricks/LTX-Video',
    local_dir='$LTX_DIR',
    local_dir_use_symlinks=False,
    allow_patterns=['*.safetensors', '*.json', '*.yaml', '*.txt', 'tokenizer/*']
)
"
fi

# Make sure ComfyUI sees the weights under its standard checkpoints/ path
# even when downloaded to /runpod-volume.
mkdir -p /opt/ComfyUI/models/checkpoints
if [ ! -L /opt/ComfyUI/models/checkpoints/LTX-Video ]; then
    ln -sfn "$LTX_DIR" /opt/ComfyUI/models/checkpoints/LTX-Video
fi

echo "→ Starting ComfyUI on 127.0.0.1:8188 (logs at /tmp/comfyui.log)"
cd /opt/ComfyUI
python main.py --listen 127.0.0.1 --port 8188 --disable-metadata --disable-auto-launch \
    > /tmp/comfyui.log 2>&1 &

echo "→ Starting RunPod handler"
cd /workspace
exec python handler.py
