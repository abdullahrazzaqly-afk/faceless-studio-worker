#!/bin/bash
# Start the RunPod handler IMMEDIATELY so the worker registers healthy with
# RunPod's rollout health check (which times out ~60-90 sec). Push the slow
# work — LTX weights download + ComfyUI boot — into a background subshell.
# The first /run request will block in handler.py's comfy_ready() poll until
# ComfyUI is up; subsequent requests are fast.

# Proof-of-life heartbeat as the very first line. If RunPod logs ever show
# "exit code 1" again with NOTHING before this line, the bug is in the image
# itself (line endings, missing bash, broken layer) — not in this script.
echo "==> CONTAINER BOOTED at $(date) — UID=$(id -u) — pwd=$(pwd)"
echo "==> bash version: $BASH_VERSION"
echo "==> Python: $(python --version 2>&1 || echo 'python not found')"

# --- Background: download LTX weights, then boot ComfyUI -------------------
(
    set -e

    if [ -d "/runpod-volume" ]; then
        MODEL_ROOT="/runpod-volume"
        echo "[bg] → Using mounted Network Volume at /runpod-volume for model cache"
    else
        MODEL_ROOT="/opt/ComfyUI/models/checkpoints"
        echo "[bg] → No Network Volume mounted — caching to container-local storage"
    fi

    LTX_DIR="$MODEL_ROOT/LTX-Video"
    mkdir -p "$LTX_DIR"

    if compgen -G "$LTX_DIR/*.safetensors" > /dev/null; then
        echo "[bg] → LTX weights already present in $LTX_DIR, skipping download"
    else
        echo "[bg] → Downloading LTX-Video weights (~22 GB, one-time)..."
        python -c "
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id='Lightricks/LTX-Video',
    local_dir='$LTX_DIR',
    local_dir_use_symlinks=False,
    allow_patterns=['*.safetensors', '*.json', '*.yaml', '*.txt', 'tokenizer/*']
)
"
        echo "[bg] → Download complete"
    fi

    # Symlink into ComfyUI's standard checkpoints dir.
    mkdir -p /opt/ComfyUI/models/checkpoints
    if [ ! -L /opt/ComfyUI/models/checkpoints/LTX-Video ]; then
        ln -sfn "$LTX_DIR" /opt/ComfyUI/models/checkpoints/LTX-Video
    fi

    echo "[bg] → Starting ComfyUI on 127.0.0.1:8188 (logs at /tmp/comfyui.log)"
    cd /opt/ComfyUI
    exec python main.py --listen 127.0.0.1 --port 8188 --disable-metadata --disable-auto-launch \
        > /tmp/comfyui.log 2>&1
) &

# --- Foreground: RunPod handler comes up immediately -----------------------
# handler.py's comfy_ready() poll will block here until the background
# subshell finishes the download + boots ComfyUI. Worker registers healthy
# from second one because handler.py is alive.
echo "==> Starting RunPod handler (background download + ComfyUI boot in progress)"
cd /workspace
exec python handler.py
