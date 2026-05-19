# Using CivitAI Wan I2V Models in Draw Things

## Overview

Draw Things can import `.safetensors` models from CivitAI. On import, it auto-converts them to its internal SQLite-based `.ckpt` format optimized for Metal/MPS. The `.ckpt` files Draw Things uses are NOT PyTorch pickles — they're proprietary SQLite databases (confirmed by developer Liu Liu in [GitHub Issue #26](https://github.com/drawthingsai/draw-things-community/issues/26)).

## CivitAI Wan I2V Model Formats

Models on CivitAI come in several formats:

| Format | Example | Draw Things? |
|--------|---------|-------------|
| **Safetensors** (fp16) | `Wan2_2-I2V-14B-fp16.safetensors` (~28GB) | Yes — auto-converts on import |
| **Safetensors** (fp8) | `Wan2_2-I2V-A14B-HIGH_fp8_e4m3fn.safetensors` (~14GB) | Risky — MPS has no FP8 compute |
| **GGUF** (quantized) | `Wan2.2-I2V-A14B-HighNoise-Q8_0.gguf` | No — not supported |
| **Diffusers** (multi-file) | Sharded across multiple files | No — need single-file repack |
| **LoRA safetensors** | `*_lora_rank_64_bf16.safetensors` | Yes |

## Import Support by Model Size

| Model | Import Custom Safetensors? | Notes |
|-------|---------------------------|-------|
| **Wan 2.2 5B** | **Yes** (since v1.20251014.0, Oct 2025) | Custom checkpoints + LoRAs explicitly supported |
| **Wan 2.2 14B** | **Risky / Undocumented** | Available via Official Models list in-app; custom 14B import not explicitly documented |
| **LoRAs (any size)** | **Yes** | CausVid, Lightning/LightX2V, Turbo LoRAs all confirmed working |

## How to Import

### Models
1. Download the `.safetensors` file from CivitAI (prefer fp16, avoid fp8/GGUF)
2. Open Draw Things > Settings > Model dropdown > **Manage**
3. Click **Import Model** > **From Files**
4. Select your downloaded `.safetensors` file
5. Draw Things converts and optimizes it for Apple hardware automatically

### LoRAs
1. Download the `.safetensors` LoRA from CivitAI or HuggingFace
2. Draw Things > Settings > Model > Manage > **Import LoRA** > **From Files**
3. Select the LoRA safetensors file

> "Installing from a downloaded file is more reliable than installing from a copied URL" — Draw Things wiki

## Compatible CivitAI / HuggingFace Downloads

### LoRAs (Safe Bets)

**Lightning / LightX2V LoRAs** — 4-step fast generation for A14B:
- `Wan_2_2_I2V_A14B_HIGH_lightx2v_4step_lora_v1030_rank_64_bf16.safetensors` (HNE)
- `Wan_2_2_I2V_A14B_LOW_lightx2v_4step_lora_v1030_rank_64_bf16.safetensors` (LNE)
- Source: [CivitAI](https://civitai.com/models/1585622/lightning-lora-massive-speed-up-for-wan21-wan22-made-by-lightx2v-kijai) or [HuggingFace (Kijai)](https://huggingface.co/Kijai/WanVideo_comfy/tree/main/LoRAs/Wan22_Lightx2v)

**CausVid LoRAs** — 4-12 step fast generation (Wan 2.1/2.2 compatible):
- Draw Things v1.20250523.0 specifically "Fixed support for Wan 2.1 CausVid LoRAs"
- Source: HuggingFace

**Turbo LoRAs** — for 5B model:
- `Wan22_TI2V_5B_Turbo_lora_rank_64_fp16.safetensors`

**Style / Motion / Character LoRAs:**
- Any Wan 2.2 compatible safetensors LoRA from CivitAI should import
- Must match model size: 14B LoRAs for 14B models, 5B LoRAs for 5B models
- Wan 2.2 14B uses dual-noise architecture: some LoRAs are split into HIGH (HNE) and LOW (LNE) variants

### Custom Checkpoints

**Wan 2.2 5B fine-tunes** — explicitly supported for import:
- Look for single-file `.safetensors` in fp16/bf16 format
- Avoid fp8 variants (MPS cannot compute with FP8)

**Wan 2.2 14B fine-tunes** (e.g., "DaSiWa TrueVision") — risky:
- The 14B architecture requires TWO models: High Noise Expert + Low Noise Expert
- Custom 14B checkpoints may not import if they don't match expected tensor names/shapes
- Safer approach: use official 14B models + CivitAI LoRAs for customization

## What NOT to Download

- **GGUF files** — ComfyUI-specific quantization format, not supported by Draw Things
- **FP8 safetensors** — MPS backend cannot cast or compute with float8_e4m3fn
- **Diffusers multi-file format** — Draw Things needs single-file checkpoints
- **SD/SDXL Wan wrappers** — some CivitAI uploads are ComfyUI workflow bundles, not raw weights

## Draw Things Internal Model Details

### Storage Location
```
~/Library/Application Support/Draw Things/models/
```

### Naming Convention
```
wan_v2.2_a14b_hne_i2v_q6p_svd.ckpt
├── wan         = model family
├── v2.2        = version
├── a14b        = parameter count (14 billion)
├── hne         = High Noise Expert
├── i2v         = image-to-video
├── q6p         = 6-bit quantization
├── svd         = SVD quantization method
└── .ckpt       = Draw Things SQLite format
```

### Quantization Variants Available In-App
- `q6p` = 6-bit (smallest, default for 14B on 48GB)
- `q8p` = 8-bit (higher quality, used for 5B)
- `f16` = full float16 (LoRAs only)

### Download CDN
Official models download from: `https://static.libnnc.org/<filename>`

### Model Version Enums (from source)
```
wan21_1_3b  — Wan 2.1 1.3B
wan21_14b   — Wan 2.1/2.2 14B (shared enum)
wan22_5b    — Wan 2.2 5B
```

## Reverse Conversion

To extract weights FROM Draw Things back to safetensors (e.g., for use in ComfyUI):
- [Draw-Things-to-Safetensors-Converter](https://github.com/EctoSpace/Draw-Things-to-Safetensors-Converter)

## References

- [Draw Things FAQ](https://wiki.drawthings.ai/wiki/FAQ)
- [Draw Things Wan 2.2 Wiki](https://wiki.drawthings.ai/wiki/Wan_2.2)
- [Install a Model or LoRA](https://wiki.drawthings.ai/wiki/Install_a_Model_or_LoRA)
- [Bring Your Own LoRA](https://wiki.drawthings.ai/wiki/Bring_Your_Own_LoRA_BYOL)
- [Draw Things Downloads / Release Notes](https://drawthings.ai/downloads/)
- [Video Generation Basics](https://wiki.drawthings.ai/wiki/Video_Generation_Basics)
- [Format Issue #26](https://github.com/drawthingsai/draw-things-community/issues/26)
