#!/bin/bash
# Boot ComfyUI in the background, then hand control to the RunPod handler.

set -e

echo "→ Starting ComfyUI on 127.0.0.1:8188 (logs at /tmp/comfyui.log)"
cd /opt/ComfyUI
python main.py --listen 127.0.0.1 --port 8188 --disable-metadata --disable-auto-launch \
    > /tmp/comfyui.log 2>&1 &

echo "→ Starting RunPod handler"
cd /workspace
exec python handler.py
