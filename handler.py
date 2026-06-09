"""
RunPod Serverless handler for Faceless Studio.

Each /run call boots ComfyUI (already running in background via start.sh),
POSTs the workflow JSON to ComfyUI's /prompt endpoint, polls /history until the
job finishes, then reads the produced MP4 off disk, base64-encodes it, and
returns it in the response.

Server.js fillLtxWorkflow() handles the placeholder substitution before this
handler ever sees the workflow; here we just forward to ComfyUI.
"""

import base64
import json
import os
import time
import uuid
import urllib.parse
import urllib.request

import runpod

COMFY_HOST = os.environ.get("COMFY_HOST", "127.0.0.1:8188")
COMFY_OUTPUT_DIR = os.environ.get("COMFY_OUTPUT_DIR", "/opt/ComfyUI/output")
POLL_INTERVAL_SEC = 1.0
MAX_WAIT_SEC = 600  # 10 minutes for the actual workflow run
# Allow up to 15 minutes for ComfyUI to come up — the background subshell in
# start.sh downloads 22 GB of LTX weights before ComfyUI boots, and that can
# take a while on cold start when there's no Network Volume cache.
COMFY_READY_TIMEOUT_SEC = 900


def comfy_ready(timeout=COMFY_READY_TIMEOUT_SEC):
    """Block until ComfyUI's HTTP server is accepting connections.

    First cold start (no Network Volume) blocks here while start.sh's
    background subshell downloads ~22 GB of LTX weights before booting
    ComfyUI. Allow plenty of slack."""
    start = time.time()
    url = f"http://{COMFY_HOST}/"
    waited_log = 0
    while time.time() - start < timeout:
        try:
            with urllib.request.urlopen(url, timeout=2) as r:
                if r.status == 200:
                    return True
        except Exception:
            pass
        time.sleep(2)
        elapsed = int(time.time() - start)
        if elapsed >= waited_log + 30:
            print(f"[handler] still waiting for ComfyUI ({elapsed}s)", flush=True)
            waited_log = elapsed
    raise RuntimeError(f"ComfyUI did not become ready within {timeout}s.")


def queue_prompt(workflow, client_id):
    body = json.dumps({"prompt": workflow, "client_id": client_id}).encode("utf-8")
    req = urllib.request.Request(
        f"http://{COMFY_HOST}/prompt",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def get_history(prompt_id):
    with urllib.request.urlopen(
        f"http://{COMFY_HOST}/history/{prompt_id}", timeout=10
    ) as r:
        return json.loads(r.read())


def find_video_file(history_entry):
    """ComfyUI saves under /output/<subfolder>/<filename>. Find the first MP4."""
    outputs = history_entry.get("outputs", {})
    for node_outputs in outputs.values():
        for key in ("videos", "gifs", "images"):
            for item in node_outputs.get(key, []) or []:
                filename = item.get("filename")
                if not filename:
                    continue
                if filename.lower().endswith((".mp4", ".webm", ".mov")):
                    subfolder = item.get("subfolder", "")
                    return os.path.join(COMFY_OUTPUT_DIR, subfolder, filename)
    return None


def handler(event):
    """RunPod serverless entry. event['input']['workflow'] holds the ComfyUI graph."""
    try:
        comfy_ready()

        payload = event.get("input") or {}
        workflow = payload.get("workflow")
        if not workflow:
            return {"error": "Missing input.workflow"}

        client_id = str(uuid.uuid4())
        submitted = queue_prompt(workflow, client_id)
        prompt_id = submitted.get("prompt_id")
        if not prompt_id:
            return {"error": f"ComfyUI rejected prompt: {submitted}"}

        # Poll /history until our prompt_id shows outputs.
        start = time.time()
        while time.time() - start < MAX_WAIT_SEC:
            history = get_history(prompt_id)
            if prompt_id in history:
                entry = history[prompt_id]
                video_path = find_video_file(entry)
                if video_path and os.path.exists(video_path):
                    with open(video_path, "rb") as f:
                        b64 = base64.b64encode(f.read()).decode("ascii")
                    return {
                        "video_base64": b64,
                        "filename": os.path.basename(video_path),
                    }
                # No video file yet but entry exists — check if it errored.
                status = entry.get("status", {})
                if status.get("status_str") == "error":
                    return {
                        "error": "ComfyUI execution failed",
                        "messages": status.get("messages", []),
                    }
            time.sleep(POLL_INTERVAL_SEC)

        return {"error": f"Timed out after {MAX_WAIT_SEC}s waiting for ComfyUI"}
    except Exception as e:
        return {"error": f"{type(e).__name__}: {e}"}


runpod.serverless.start({"handler": handler})
