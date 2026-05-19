# Draw Things Configuration Reference — M4 Pro 48GB

Last updated: 2026-02-06

## Hardware
- MacBook Pro M4 Pro, 20 GPU cores, 48GB unified RAM
- Metal FlashAttention v2.5 enabled (Neural Accelerator path is M5-only)
- Draw Things version: 1.20260120.0

---

## VIDEO: Wan 2.2 I2V 14B (Image-to-Video)

### Key Facts
- **Only valid I2V model**: Wan 2.2 A14B HNE + LNE (High/Low Noise Expert split)
- **Supported 480p resolution**: 448×768 (confirmed by Draw Things engineering blog)
- **The 5B TI2V model does NOT preserve input images** — it's mostly T2V, not real I2V
- **832×832 is NOT a valid Wan 2.2 resolution** — produces garbage output
- **Lightning LoRAs are incompatible with q6p SVDQuant models** — causes color shifts and artifacts
- **The refiner model MUST be LNE**, never HNE — using HNE as refiner produces washed-out garbage
- **LoRA modes matter**: HNE LoRA = "base" mode only, LNE LoRA = "refiner" mode only. Never use "all".
- **TeaCache should NOT be used with low step counts** (7 or fewer) — causes massive quality loss
- **Draw Things auto-downscales images to non-standard resolutions** — always pre-crop images to exact target dimensions

### Community Config: WAN v2.2 I2V 14B with Lightning v1.0 (~20 min, 4 steps)

```json
{
  "model": "wan_v2.2_a14b_hne_i2v_q6p_svd.ckpt",
  "refinerModel": "wan_v2.2_a14b_lne_i2v_q6p_svd.ckpt",
  "refinerStart": 0.1,
  "steps": 4,
  "guidanceScale": 1,
  "shift": 5,
  "sampler": 17,
  "cfgZeroStar": false,
  "numFrames": 81,
  "width": 832,
  "height": 448,
  "loras": [
    {"mode": "base", "file": "wan_v2.2_a14b_hne_i2v_lightning_v1.0_lora_f16.ckpt", "weight": 1.0},
    {"mode": "refiner", "file": "wan_v2.2_a14b_lne_i2v_lightning_v1.0_lora_f16.ckpt", "weight": 1.0}
  ],
  "teaCache": false,
  "seedMode": 2,
  "preserveOriginalAfterInpaint": true
}
```

**IMPORTANT**: For portrait images, swap width/height to 448×832. Pre-crop input images to exact dimensions.

**Generation time on M4 Pro**: ~20 minutes for 33 frames at 448×832.

**Known issue**: Lightning LoRAs were trained on full-precision models. With q6p SVDQuant, color shifts may occur. If so, remove LoRAs and use 20-30 steps instead.

### Recommended Config: WAN v2.2 I2V 14B (no LoRA, 30 steps, ~90 min)

```json
{
  "model": "wan_v2.2_a14b_hne_i2v_q6p_svd.ckpt",
  "refinerModel": "wan_v2.2_a14b_lne_i2v_q6p_svd.ckpt",
  "refinerStart": 0.1,
  "steps": 30,
  "guidanceScale": 3.5,
  "shift": 5,
  "sampler": 17,
  "cfgZeroStar": false,
  "numFrames": 81,
  "width": 448,
  "height": 832,
  "loras": [],
  "teaCache": false,
  "seedMode": 2,
  "preserveOriginalAfterInpaint": true
}
```

**Generation time on M4 Pro**: ~90 min for 33 frames, ~6-7 hours for 81 frames.

### Tutorial Chaining Technique (from Cutscene Artist)
1. Generate a short clip (33-57 frames, vary count to avoid repetition)
2. Do NOT play the video when it finishes
3. Leave the last frame on the canvas — it becomes the start frame for the next clip
4. Prompt only the NEW action (one action per clip, keep prompts short)
5. Repeat, varying frame count each time
6. Export all clips together: Version History → right-click → select multiple → shift-click all → export as video
7. Use ProRes422HQ for editing, H.264 for sharing

### Tutorial Settings (from transcript)
- HNE Lightning LoRA: 90% weight
- LNE Lightning LoRA: 80% weight (higher overcooks)
- Refiner start: 12.5%
- Steps: 7 (with Lightning)
- CFG-Zero*: On but set to 0
- Sampler: DDIM Trailing
- Shift: 3 (default 5; use higher like 12 for small figures in wide shots)
- Portrait orientation for people (makes face bigger = more detail preserved)
- Vary frame counts: 33, 37, 41, 49, 52, 57

---

## IMAGE EDITING: Qwen Image Edit 2511 + Lightning 4-Step

### Key Facts
- Purpose-built for image editing: change costume, scene, pose, expression
- Canvas = source photo ("Picture 1")
- Moodboard/Creative Board = reference images ("Picture 2", "Picture 3", etc.)
- Natural language prompts: "Change the costume to a red dress"
- AnyPose LoRA available for pose transfer without ControlNet preprocessing
- Largely uncensored out of the box
- On M4 Pro 48GB, can run full BF16 Exact variant (~30 GiB peak)

### Config: Qwen Image Edit 2511 Lightning 4-Step

| Setting | Value |
|---|---|
| Model | Qwen Image Edit 2511 (BF16 Exact) |
| LoRA | Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16 (weight 1.0) |
| Steps | 4 |
| Guidance | 1.0 (CFG-distilled, do not increase) |
| Shift | 2.33 - 2.83 |
| Sampler | DDIM (sampler 17) |
| Resolution | 768×768 or 1024×1024 |
| Strength | 1.0 |
| Mask Blur | 1.5 |

**Do NOT use the 2509 Lightning LoRA with the 2511 model.**

### Workflow
1. Load source photo onto Canvas
2. (Optional) Load reference images onto Moodboard for costume/scene refs
3. (Optional) Load pose reference onto Moodboard + use AnyPose LoRA
4. Write natural-language prompt describing changes
5. For inpainting: use Eraser to mask area, describe only NEW content
6. Use "preserve" language for things to keep (e.g., "preserve face identity")
7. Do one change at a time to avoid drift

---

## IMAGE GENERATION: Qwen Image 2512 + Turbo 2-Step (FASTEST)

### Config: Qwen Image 2512 Turbo 2-Step

| Setting | Value |
|---|---|
| Model | qwen_image_2512_bf16_q6p.ckpt |
| LoRA | Wuli-Qwen-Image-2512-Turbo-LoRA-2steps-V1.0-bf16 (weight 0.95) |
| Steps | 2-3 |
| Guidance | 1.0 |
| Shift | 1.02 |
| Sampler | 9 |
| Resolution | 1152×768 or 1328×1328 |

### Config: Qwen Image 2512 Lightning 4-Step

| Setting | Value |
|---|---|
| Model | Qwen Image 2512 (BF16) |
| LoRA | Qwen-Image-2512-Lightning (weight 1.0) |
| Steps | 4 |
| Guidance | 1.0 |
| Resolution | 1328×1328 or 1664×928 (16:9) |

### Prompting Tips
- Front-load primary subject
- Add style suffixes: "Ultra HD, 4k, cinematic composition"
- Leave negative prompt empty or simple ("blurry")

---

## UNCENSORED SDXL: Pony Diffusion XL

### Config: PonyXL

| Setting | Value |
|---|---|
| Model | Pony Diffusion XL (import .safetensors from Civitai) |
| **CLIP Skip** | **2** (CRITICAL — breaks without this) |
| CFG | 5-7 |
| Steps | 20-30 |
| Sampler | Euler Ancestral or DPM++ |
| Resolution | 1024×1024 |
| VAE | Pony XL VAE |

Also consider: CyberRealistic Pony (realistic style, uncensored)

---

## Machine Settings (M4 Pro 48GB)

| Setting | Value | Why |
|---|---|---|
| Keep Model in Memory | **Yes** | Avoids 2-5s reload between generations |
| Use CoreML | **No** | Not used for Wan/Qwen models |
| JIT Weights Loading | **Never** | JIT is for low-RAM devices |
| Weights Cache Size | **24 GiB** (max available) | Keeps models cached |
| Metal Flash Attention | **Yes** | Critical for speed |
| Video Export Format | **ProRes422HQ** | High quality without bloat |
| LoRA weights merging | **Not for Quantized Models** | Preserves quantization benefits |
| High Power Mode | **Enable in System Settings** (when plugged in) | Full GPU clocks |

---

## Looping Wan 2.2 Clips

**Don't use ComfyUI's WanVideoWrapper loop path** — it has a known contrast-creep bug ([#1541](https://github.com/kijai/ComfyUI-WanVideoWrapper/issues/1541)). The `uniform_looped` context option also has black frame / color anomaly bugs ([#412](https://github.com/kijai/ComfyUI-WanVideoWrapper/issues/412)).

**Recommended approach:** Generate normal i2v in Draw Things → ping-pong loop in FFmpeg. See `wan22_draw_things_notes.md` for the FFmpeg command and color-lock script.

For **first/last frame workflows**, a Discord script enables FLF2V in Draw Things — see `wan22_draw_things_notes.md`.

---

## Alibaba Model Censorship Notes

- **Alibaba Cloud (Model Studio / hosted APIs)**: moderated. Content Moderation blocks pornography, political content, ads, etc. Tracked in telemetry. ([docs](https://www.alibabacloud.com/help/en/model-studio/model-telemetry/))
- **Local open weights (Draw Things, ComfyUI, etc.)**: mostly unconstrained — no external moderation layer. But training can still bake in refusals/avoidance or style collapse on certain prompts.
- **Qwen-Image specifically**: largely uncensored locally — public reports confirm it can generate adult content if guided. ([HF discussion](https://huggingface.co/Qwen/Qwen-Image/discussions/21))
- **"Uncensored" is not binary**: cloud = moderated, local = generally freer, but training-level biases remain.

---

## Lessons Learned (2026-02-07)

1. **Always verify resolution is supported by the model** before generating
2. **Pre-crop input images to exact target dimensions** — don't let Draw Things auto-scale
3. **Never use HNE model as refiner** — always use LNE
4. **LoRA modes must match**: base LoRA → "base" mode, refiner LoRA → "refiner" mode
5. **Lightning/Turbo LoRAs require low guidance** (~1.0) — standard guidance (3.5+) breaks them
6. **TeaCache + low steps = quality collapse** — only use TeaCache with 20+ steps
7. **Lightning LoRAs + quantized models can cause color shifts** — test before committing to long renders
8. **M4 Pro + Wan 14B = slow** — expect 20-90 min per clip depending on steps/LoRA
9. **5B TI2V is NOT a real I2V model** — it ignores input images
10. **For fast image editing, use Qwen Image Edit** — seconds per image vs hours for video
11. **ComfyUI loop nodes (WanVideoWrapper) have contrast-creep and color bugs** — use ping-pong FFmpeg instead
12. **Draw Things works better on Mac because it ships Mac-targeted weights** — ComfyUI inherits PyTorch MPS FP8 dtype gaps
13. **For looping, ping-pong in FFmpeg is the most reliable approach** — avoids all Wan loop-math issues

## Sources
- [Draw Things Wiki](https://wiki.drawthings.ai/)
- [Draw Things Wan 2.2 Wiki](https://wiki.drawthings.ai/wiki/Wan_2.2)
- [Metal FlashAttention v2.5 blog](https://engineering.drawthings.ai/p/optimizing-qwen-image-for-edge-devices)
- [Wan 2.2 GitHub](https://github.com/Wan-Video/Wan2.2)
- [Draw Things Community GitHub](https://github.com/drawthingsai/draw-things-community)
- [Qwen-Image-Edit-2511-Lightning](https://huggingface.co/lightx2v/Qwen-Image-Edit-2511-Lightning)
- [Wuli Turbo LoRA](https://huggingface.co/Wuli-art/Qwen-Image-2512-Turbo-LoRA-2-Steps)
- [WanVideoWrapper Loop Bug #1541](https://github.com/kijai/ComfyUI-WanVideoWrapper/issues/1541)
- [uniform_looped Bug #412](https://github.com/kijai/ComfyUI-WanVideoWrapper/issues/412)
- [ComfyUI FP8/MPS Fix PR #23](https://github.com/Comfy-Org/comfy-kitchen/pull/23)
- [ComfyUI FP8/MPS Issue #8988](https://github.com/Comfy-Org/ComfyUI/issues/8988)
- [Alibaba Model Studio Telemetry](https://www.alibabacloud.com/help/en/model-studio/model-telemetry/)
- [Qwen-Image Censorship Discussion](https://huggingface.co/Qwen/Qwen-Image/discussions/21)
