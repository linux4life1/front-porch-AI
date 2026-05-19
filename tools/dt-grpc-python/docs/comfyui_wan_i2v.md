# ComfyUI Wan 2.2 I2V on Mac — Status & Workarounds

## Current State (Feb 2026)

ComfyUI can run Wan 2.2 I2V on Mac via the MPS (Metal Performance Shaders) backend, but with significant limitations compared to CUDA. The main blockers are FP8 support and memory management.

## Key Blockers on MPS

### 1. FP8 Tensors — NOT Supported on MPS

PyTorch's MPS backend **cannot cast to or compute with FP8** (float8_e4m3fn/float8_e5m2):
- Can create and transfer FP8 tensors, but NO arithmetic operations
- `torch._scaled_mm` is not implemented for MPS
- This blocks FLUX, SD3.5, and any model stored as FP8

**Impact:** Many CivitAI Wan checkpoints are distributed as FP8 to save VRAM. These will NOT work directly on MPS.

**Workarounds:**
- Use fp16/bf16 checkpoints instead of fp8 (2x larger but work natively)
- CPU fallback: dequant FP8→FP16 on CPU then transfer to MPS (3.74x slower than native FP16)
- Custom Metal kernel: See `mps/fp8_metal/` in this repo for a GPU-accelerated FP8 dequant solution

### 2. quantize_per_tensor — NOT Supported

No native quantized tensor support on MPS. Affects INT8/INT4 quantized models from ComfyUI nodes like `QuantizedModel`.

### 3. Memory Management

- MPS per-buffer hard cap: **32GB** (Metal limit)
- With `PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0`: up to 28GB per buffer
- Full 48GB accessible via multiple <32GB buffers (multi-buffer sharding)
- Wan 2.2 14B at fp16 ≈ 28GB — fits in a single buffer at watermark=0.0
- Wan 2.2 14B at fp8 ≈ 14GB — but can't compute, so useless on MPS

### 4. Missing CUDA-Specific Ops

Some ComfyUI custom nodes use CUDA-only operations:
- `torch.linalg.eigh`, `torch.linalg.qr` — fail on MPS
- `torch.svd` — falls back to CPU (slow but works)
- FlashAttention — not available, uses standard attention (higher memory)

## Working ComfyUI Wan I2V Setup on Mac

### Model Files Needed

From CivitAI or HuggingFace — **must be fp16/bf16, NOT fp8**:

```
models/diffusion_models/
  Wan2_2-I2V-14B-HIGH-fp16.safetensors     # High Noise Expert (~28GB)
  Wan2_2-I2V-14B-LOW-fp16.safetensors      # Low Noise Expert (~28GB)
  # OR
  wan2.2_5b_ti2v_fp16.safetensors          # 5B unified model (~10GB)

models/vae/
  wan_2.2_vae.safetensors                  # VAE decoder (~1.4GB)

models/clip/
  umt5xxl_fp16.safetensors                 # Text encoder (~10GB)
  # OR use fp8 text encoder (works for encoding, not diffusion)

models/clip_vision/
  clip_vision_h.safetensors                # CLIP vision for I2V
```

### Recommended CivitAI Downloads

**For 48GB Mac (M4 Pro/Max):**

| Model | CivitAI Link | Size | Notes |
|-------|-------------|------|-------|
| Wan 2.2 I2V 14B HNE fp16 | Search "Wan 2.2 I2V 14B" | ~28GB | Use fp16, NOT fp8 |
| Wan 2.2 I2V 14B LNE fp16 | Same page, LNE variant | ~28GB | Required for dual-expert |
| Wan 2.2 5B ti2v | Search "Wan 2.2 5B" | ~10GB | Simpler, fits easily |
| Lightning LoRA (HNE) | [CivitAI](https://civitai.com/models/1585622) | ~400MB | 4-step fast gen |
| Lightning LoRA (LNE) | Same page | ~400MB | Pair with HNE |
| Wan VAE | Included with model pages | ~1.4GB | Required |

**For 16-24GB Mac (M3 Pro, M2 Pro):**

| Model | Size | Notes |
|-------|------|-------|
| Wan 2.2 5B ti2v q8 GGUF | ~5GB | ComfyUI GGUF loader node required |
| Wan 2.2 5B ti2v fp16 | ~10GB | Standard, fits in 16GB with offloading |

### ComfyUI Nodes for Wan I2V

Essential custom nodes:
- **ComfyUI-WanVideoWrapper** (Kijai) — Primary Wan 2.2 node pack
- **ComfyUI-GGUF** — For loading GGUF quantized models
- **ComfyUI-VideoHelperSuite** — Frame handling, video I/O

### Environment Variables for MPS

```bash
# Allow MPS to use all available memory
export PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0

# Force MPS backend
export PYTORCH_ENABLE_MPS_FALLBACK=1

# Reduce memory fragmentation
export PYTORCH_MPS_ALLOCATOR_POLICY=garbage_collection
```

### Sample ComfyUI Workflow (Wan 2.2 5B I2V on Mac)

Key node settings for MPS:
```
WanVideoSampler:
  - model: wan2.2_5b_ti2v_fp16.safetensors
  - steps: 20 (or 4-8 with Lightning/Turbo LoRA)
  - cfg: 5.0-7.5 (standard model) or 1.0 (with Lightning LoRA)
  - scheduler: ddim_trailing
  - denoise: 1.0
  - num_frames: 33
  - width: 640
  - height: 384
  - device: mps
```

## Draw Things vs ComfyUI Comparison (Mac)

| Feature | Draw Things | ComfyUI (MPS) |
|---------|------------|---------------|
| **Setup** | One-click install | Python env + custom nodes |
| **Model format** | Proprietary .ckpt (auto-downloads) | Safetensors/GGUF (manual download) |
| **FP8 support** | No (same Metal limitation) | No (same limitation) |
| **Quantization** | q6p/q8p built-in | GGUF via custom node |
| **14B I2V** | Official models, optimized | Manual setup, fp16 only on MPS |
| **5B I2V** | Official + custom import | Full flexibility |
| **LoRA support** | Import safetensors | Native safetensors loading |
| **Speed (5B 33f)** | ~104s via gRPC benchmark | ~120-150s est (less optimized Metal path) |
| **Memory efficiency** | Better (NNC optimized) | Worse (generic PyTorch MPS) |
| **Workflow flexibility** | Limited (UI + JS scripting) | Full node graph, any combination |
| **Custom nodes** | No | Yes (ControlNet, IP-Adapter, etc.) |

## Performance Tips for ComfyUI on Mac

1. **Use fp16, not fp8** — fp8 will fail or fall back to slow CPU path
2. **Use 5B model for speed** — 14B requires loading 2x 28GB models sequentially
3. **Set `PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0`** — prevents OOM at 70% memory
4. **Reduce resolution first** — 640x384 is 1.7x fewer pixels than 832x448
5. **Fewer steps with LoRA** — Lightning LoRA at 4 steps >> standard 20 steps
6. **GGUF Q8 for 14B** — if available, Q8 GGUF (~14GB) fits better than fp16 (~28GB)
7. **Disable preview** — real-time preview adds ~10% overhead on MPS
8. **Close other GPU apps** — MPS shares unified memory with everything

## Known Issues

- **FlashAttention not available on MPS** — falls back to standard attention, higher memory usage
- **Some ComfyUI nodes assume CUDA** — check node compatibility before installing
- **MPS kernel dispatch overhead** — ~10% higher than CPU for small operations; prefer fewer, larger ops
- **Video VAE decode can OOM** — decode frames in batches of 4-8 instead of all at once

## References

- [ComfyUI-WanVideoWrapper](https://github.com/kijai/ComfyUI-WanVideoWrapper)
- [PyTorch MPS Backend](https://pytorch.org/docs/stable/notes/mps.html)
- [CivitAI Wan 2.2 Models](https://civitai.com/models?query=wan+2.2+i2v)
- [HuggingFace Kijai WanVideo](https://huggingface.co/Kijai/WanVideo_comfy)
- [ComfyUI GGUF Nodes](https://github.com/city96/ComfyUI-GGUF)
