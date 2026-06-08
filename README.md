# Faceless Studio — RunPod Serverless Worker

This is the GPU-side worker for [Faceless Studio](../). It runs ComfyUI plus
LTX-Video 2.3 inside a RunPod Serverless endpoint and exposes a single
`/run` HTTP route that your local Node server hits.

## What's in the box

| File | Purpose |
|---|---|
| `Dockerfile` | Builds a CUDA-12.1 image with ComfyUI + LTX-2.3 weights baked in. ~28 GB final size. |
| `handler.py` | RunPod serverless entry point. Boots ComfyUI in the background, forwards `/run` requests to ComfyUI's `/prompt` endpoint, returns the produced MP4 as base64. |
| `start.sh` | Boots ComfyUI on `127.0.0.1:8188` then launches the RunPod handler. |
| `requirements.txt` | `runpod` + `requests`. Everything else lives in the ComfyUI install. |

## Deploy

1. Push this folder as a new GitHub repo (any name, public or private).
2. On RunPod, **Serverless → New Endpoint → Deploy from a GitHub repository**.
3. Connect your repo, choose `main` branch, point at this folder if not at the root.
4. GPU pool: **RTX 4090** (24 GB).
5. Workers: **Min 0, Max 1**. Idle timeout **30 sec**. FlashBoot **ON**.
6. Deploy. First build takes 20-30 minutes (weights download). Subsequent builds reuse layers.
7. Copy the **Endpoint ID** and an **API key** from the RunPod dashboard into your local `.env`:

```env
RUNPOD_API_KEY=...
RUNPOD_ENDPOINT_ID=...
```

## How it's called

Your local server posts to `https://api.runpod.ai/v2/<endpoint>/run` with:

```json
{
  "input": {
    "workflow": { /* ComfyUI workflow_api.json with LTX I2V graph */ }
  }
}
```

The workflow is built from `templates/ltx-i2v.json` in the parent project, with placeholders substituted per beat:

- `{{PROMPT}}` — visual_prompt from the beat sheet
- `{{KEYFRAME_B64}}` — base64 PNG from Gemini
- `{{FRAMES}}` — duration_sec × 24
- `{{WIDTH}}` / `{{HEIGHT}}` — from aspect ratio
- `{{SEED}}` — random per call

The handler polls ComfyUI's `/history/{prompt_id}` once per second until an MP4 appears under `/opt/ComfyUI/output/`, then returns:

```json
{ "video_base64": "...", "filename": "..." }
```

## Tuning

Edit `Dockerfile` to swap weights or add other custom nodes. Common changes:

- Different LTX checkpoint: change the `hf_hub_download` filename
- Bigger T5 encoder: swap `google/flan-t5-xxl`
- Smaller image: skip T5 and use ComfyUI's built-in encoder (slightly lower quality)
