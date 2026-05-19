# Draw Things on Mac M4 — image-to-video (I2V) reference

Short reference for running **image-to-video** (photo → short animated clips) locally on your **M4 MacBook Pro, 48GB**. Condensed from community guides and Draw Things wiki.

---

## Why Draw Things (not ComfyUI) on your Mac

- **Draw Things** = native macOS app, **Metal-optimized** for Apple Silicon. Best local option for I2V on M4.
- **ComfyUI** = PyTorch/MPS on Mac; often slower, more fiddly (dtype/float8 issues, CPU fallbacks). Use it only if you need extreme node-based control.
- **48GB unified memory** = plenty for 14B WAN models (~20–25GB peak); headroom for LoRAs, chaining, multitasking.

### The technical reason Draw Things is better on Mac

Draw Things ships **Mac-targeted converted models** (q6p SVDQuant) and a pipeline designed around Metal constraints. Your config (quantized base + f16 LoRAs + lightning 4-step) stays on a happy path because the dtypes and kernels are all Apple Silicon native.

ComfyUI inherits **PyTorch MPS limitations**. The critical one: **MPS cannot operate on FP8 tensors** (`float8_e4m3fn` / `float8_e5m2`), and many modern diffusion weights ship in FP8 to save VRAM on CUDA. When ComfyUI hits FP8 weights on Mac, it either crashes ("Trying to convert Float8… to the MPS backend but it does not have support for that dtype") or falls back to a compatibility patch ([comfy-kitchen PR #23](https://github.com/Comfy-Org/comfy-kitchen/pull/23)) that dequantizes on CPU and shuttles tensors back to GPU — introducing **CPU↔GPU transfers** in the middle of your graph, which is brutally slow and fragile.

**Bottom line:** Draw Things = integrated Apple-native pipeline. ComfyUI on Mac = general PyTorch/MPS pipeline with workaround PRs for dtype gaps.

---

## Get Draw Things without Apple ID

- **Downloads page:** https://drawthings.ai/downloads/
- **Direct zip (example build):** https://static.drawthings.ai/DrawThings-1.20260120.0-3a5a4a68.zip  
  (Check the downloads page for newer builds; pattern: `https://static.drawthings.ai/DrawThings-<version>-<hash>.zip`)
- Unzip → drag app to Applications.
- First launch: if Gatekeeper blocks, **System Settings → Privacy & Security → Open Anyway**.
- This build has **no cloud compute**; all local. Updates = manual re-download from the same page.

---

## Recommended models for your setup (WAN 2.2 I2V)

| Use | Model | Notes |
|-----|--------|------|
| **Base (best quality)** | **Wan 2.2 High Noise Expert I2V A14B** | ~20–25GB peak. Best for motion/scene/composition. Use as base, then refiner. |
| **Lighter option** | Wan 2.2 High Noise Expert I2V A14B **6-bit SVDQuant** | ~15–20GB, minimal quality loss. |
| **Refiner** | **Wan 2.2 Low Noise Expert I2V A14B** (full or 6-bit) | Use *after* High Noise for polish, temporal consistency, fewer artifacts. |
| **Skip / low priority** | Wan 2.2 5B, 8-bit; Wan 2.1 | Lower quality/motion; only for testing or low-RAM. |

All available in Draw Things **Official Models** (in-app Model Manager).

---

## Basic workflow in Draw Things

1. **Video** tab → select **High Noise Expert I2V A14B** as base.
2. Upload your photo → add motion prompt (e.g. *"woman twirling in dress, seductive dance, smooth camera zoom, cinematic"*).
3. Enable **Refiner** → set **Low Noise Expert**.
4. Generate at **576×1024** or **720p** (balance quality/speed). Chain outputs (feed result back in) for 10–20s+ clips.
5. Optional: add **LoRAs** (Civitai) for style/face consistency.

Expect **~1–5+ min per short clip** depending on resolution/frames/steps. Plug in; enable “Universal Weights Cache” in settings if offered for 48GB+.

---

## How those “viral” clips are usually made

- **Prompt-based:** One image + text prompt for motion (e.g. “dancing,” “twirl,” “camera pan”). Draw Things + WAN does this well.
- **Precise motion:** Reference video → extract poses (DWPose/OpenPose) → apply to your image. That’s the “whatever they want” control; typically done in ComfyUI with AnimateDiff + ControlNet. On Mac, Draw Things is still the smoother choice for prompt-based I2V; use ComfyUI only if you need that exact pose-transfer workflow.

---

## Looping video clips

The **WanVideoWrapper loop path** in ComfyUI has a known contrast-creep bug ([#1541](https://github.com/kijai/ComfyUI-WanVideoWrapper/issues/1541)), and the `uniform_looped` context option has its own bugs (black frames, color anomalies — [#412](https://github.com/kijai/ComfyUI-WanVideoWrapper/issues/412)). Draw Things doesn't use these wrappers, so the simplest stable loop is **ping-pong** (forward then reverse):

### FFmpeg ping-pong loop (seamless, no Wan loop math)

```bash
ffmpeg -i clip.mp4 -filter_complex \
"[0:v]split[a][b]; \
 [b]reverse,select='not(eq(n,0))',setpts=N/FRAME_RATE/TB[br]; \
 [a][br]concat=n=2:v=1:a=0,format=yuv420p[v]" \
-map "[v]" loop_pingpong.mp4
```

This drops the duplicated seam frame and produces a seamless loop for motion use cases (walk cycles, hair/cloth movement, subtle camera sway).

### Color-lock post-processing (fix brightness/contrast drift)

If you see slight drift across frames, match every frame's RGB mean/std to frame 0:

```bash
mkdir -p frames_in frames_out
ffmpeg -i clip.mp4 frames_in/%05d.png
python3 color_lock.py          # see wan22_draw_things_notes.md for script
ffmpeg -framerate 16 -i frames_out/%05d.png -pix_fmt yuv420p color_locked.mp4
```

### First/Last Frame to Video (FLF2V)

**Script:** `community-scripts/scripts/flf2v/flf2v.js` — experimental FLF2V using Wan 2.1 Fun Inpainting model. Two modes:
1. **Fun Inpainting** (experimental): first frame on canvas + last frame as custom layer + `wan_2.1_14b_fun_inp_q6p_svd.ckpt`
2. **Standard I2V** (fallback): first frame only, then ping-pong loop in FFmpeg

See `wan22_draw_things_notes.md` for details on limitations and findings. See also [Reddit thread](https://www.reddit.com/r/drawthingsapp/comments/1mw85cz/is_there_a_way_to_do_first_frame_last_frame/).

---

## Quick links

- **Draw Things downloads:** https://drawthings.ai/downloads/
- **Direct zip (example):** https://static.drawthings.ai/DrawThings-1.20260120.0-3a5a4a68.zip
- **Site / wiki:** https://drawthings.ai/
- **Civitai:** models, LoRAs, motion modules, workflows (search “AnimateDiff”, “image to video”, “WAN”).
- **Reddit:** r/drawthingsapp, r/StableDiffusion, r/comfyui for Mac-specific tips.
