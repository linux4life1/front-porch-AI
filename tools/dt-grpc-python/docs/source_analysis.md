# Draw Things Source Code Analysis

> Deep analysis of draw-things-community internals for optimization.
> Extracted from Swift source code, 2026-02-07.

---

## Repository Structure

```
draw-things-community/
├── BUILD                     # Empty stub
├── WORKSPACE.darwin          # Bazel workspace (macOS)
├── MODULE.bazel              # Bazel 8 config
├── .bazelrc.darwin           # MPS enabled by default
├── .bazelversion             # 7.4.1
├── Apps/                     # CLI tools only (GUI is private)
│   ├── gRPCServerCLI/       # Main buildable binary
│   ├── ModelConverter/
│   ├── LoRAConverter/
│   ├── ModelQuantizer/
│   └── EmbeddingConverter/
├── Libraries/                # 256 MB — all core code
│   ├── SwiftDiffusion/      # Core ML inference (101 Swift files)
│   ├── ModelZoo/            # Model registry + coefficients
│   ├── LocalImageGenerator/
│   ├── Scripting/           # JavaScript API bridge
│   ├── WeightsCache/
│   └── ...27 more
├── Vendors/                  # 28 MB vendored deps
└── Scripts/                  # Build scripts
```

**Key fact:** The full Draw Things GUI app code is NOT in this repo. Only the inference engine (SwiftDiffusion), CLI tools, and library code are open-source.

---

## Build System

- **Bazel 7.4.1** (not Swift Package Manager or Xcode)
- 40+ external dependencies auto-downloaded
- Metal enabled by default via `.bazelrc.darwin`
- Build: `bazel build Apps:gRPCServerCLI-macOS --config=release`
- Requires full Xcode (not just CLT)

---

## Wan Model Implementation

### Wan.swift (1302 lines)

**Location:** `Libraries/SwiftDiffusion/Sources/Models/Wan.swift`

Core model implementation with:
- **Flash Attention v2.5** — Metal-optimized multi-head attention
- **Causal inference** — Sliding window attention over video frames (not full O(T^2))
- **LoRA support** — Separate `LoRAWan` variant with adapter hooks
- **Configurable architecture:**
  ```swift
  Wan(
    channels: Int,          // 3072 (5B) or 5120 (14B)
    layers: Int,            // 30 (5B) or 40 (14B)
    vaceLayers: [Int],      // VACE conditioning layers (14B only)
    intermediateSize: Int,  // 14336 (5B) or 13824 (14B)
    time: Int,              // batch size
    height: Int, width: Int,
    textLength: Int,
    causalInference: Bool,
    injectImage: Bool,
    usesFlashAttention: Bool,
    outputResidual: Bool,   // TeaCache: output hidden state residual
    inputResidual: Bool,    // TeaCache: accept cached residual as input
    outputChannels: Int     // 48 (5B) or 16 (14B)
  )
  ```

### WanVAE.swift (~400 lines)

**Location:** `Libraries/SwiftDiffusion/Sources/Models/WanVAE.swift`

- **3D causal attention** VAE for video
- **Wan 2.2 per-frame shortcuts** — faster decoding
- Processes frames sequentially (potential optimization: batch frames)

### Key Architecture Parameters

| Parameter | Wan 2.2 5B (`.wan22_5b`) | Wan 2.2 A14B (`.wan21_14b`) |
|---|---|---|
| Channels | 3,072 | 5,120 |
| Layers | 30 | 40 |
| Intermediate Size | 14,336 | 13,824 |
| Output Channels | 48 | 16 |
| VACE Layers | None | [0, 5, 10, 15, 20, 25, 30, 35] |
| VAE | wan_v2.2_video_vae_f16 | wan_v2.1_video_vae_f16 |
| FPS | 24 | 16 |
| Tile Scale Factor | 4 | 8 |

---

## Denoising Pipeline

### DDIMSampler.swift (762 lines)

**Location:** `Libraries/SwiftDiffusion/Sources/Samplers/DDIMSampler.swift`

Main denoising loop:
1. Initialize noise schedule
2. For each step:
   - Compute time embedding
   - Check TeaCache: skip if cached residual is fresh enough
   - Run UNet forward pass (or use cached result)
   - Apply CFG: `et = et_uncond + guidance * (et_cond - et_uncond)`
   - DDIM step: update latent
3. If refiner model configured:
   - Switch model at `refinerStart` fraction
   - Continue denoising with refiner

### UNetProtocol.swift (~3400 lines)

**Location:** `Libraries/SwiftDiffusion/Sources/Models/UNetProtocol.swift`

This is the most important file — it orchestrates:
1. **Model creation** (lines 1073-1168 for wan22_5b/wan21_14b)
2. **TeaCache setup** (creates reducedModel with 0 hidden layers)
3. **Forward pass dispatch** (lines 2536-2650 for Wan models)
4. **CFG splitting** (separate uncond/cond passes)
5. **Model weight loading** with LoRA key mapping
6. **Tiled diffusion** coordination

### Forward Pass for Wan (UNetProtocol.swift:2536-2650)

```
for each step:
  1. shouldUseCache = teaCache.shouldUseCacheForTimeEmbedding(
       timeEmbeddings, model, step, marker)

  2. if CFG enabled:
     a. Split input into uncond/cond halves
     b. For uncond: if cache hit → use cached residual
                    else → run full UNet, cache residual
     c. For cond:   same cache check
     d. Concatenate results

  3. if no CFG:
     a. Cache check → run or reuse
```

---

## TeaCache Implementation

### TeaCache.swift (212 lines)

**Location:** `Libraries/SwiftDiffusion/Sources/TeaCache/TeaCache.swift`

#### Data Flow

```
TeaCacheConfiguration
  ├── coefficients: (Float, Float, Float, Float, Float)  // 4th degree polynomial
  ├── steps: ClosedRange<Int>     // Active step range
  ├── threshold: Float            // Skip threshold
  └── maxSkipSteps: Int           // Max consecutive skips

TeaCache<FloatType>
  ├── reducedModel: Model         // 0 hidden layers (shift/scale only)
  ├── inferModel: Model?          // Time embedding normalizer (Flux1/HunyuanVideo only)
  ├── lastTs: [Int: [Tensor]]     // Previous time embeddings per marker
  ├── accumulatedRelL1Distances: [Int: Float]
  ├── lastResiduals: [Int: Tensor] // Cached outputs
  └── skipSteps: [Int: Int]       // Consecutive skip counter
```

#### Algorithm

```
shouldUseCacheForTimeEmbedding(t, model, step, marker):
  if no lastT or step not in range or skipCount >= maxSkip:
    save t, reset accumulator → return false (run full model)

  r = mean(|t - lastT|) / mean(|lastT|)                    // Normalized L1 distance
  dist = c[0]*r^4 + c[1]*r^3 + c[2]*r^2 + c[3]*r + c[4]  // Polynomial mapping
  accumulated += dist

  if accumulated >= threshold:
    reset accumulated → return false (run full model)

  return true (use cache)

callAsFunction(model, inputs, marker):
  shift = restInputs[-2]
  scale = restInputs[-1]
  return reducedModel(input, lastResidual, shift, scale)  // Near-zero compute
```

#### Models with TeaCache Support

| Model Version | inferModel | reducedModel | Coefficients Source |
|---|---|---|---|
| `.flux1` | YES (time normalization) | 0-layer model | Hardcoded fallback |
| `.hunyuanVideo` | YES (time normalization) | 0-layer model | Hardcoded fallback |
| `.hiDreamI1` | NO | 0-layer model | Hardcoded fallback |
| `.wan21_1_3b` | NO | 0-layer Wan | From ModelZoo |
| `.wan21_14b` | NO | 0-layer Wan | From ModelZoo |
| **`.wan22_5b`** | NO | **MISSING** | `nil` (not implemented) |

---

## ModelZoo — TeaCache Coefficients

### Wan 2.1 / 2.2 T2V Models

```swift
// T2V 1.3B (wan21_1_3b)
[-5.21862437e+04, 9.23041404e+03, -5.28275948e+02, 1.36987616e+01, -4.99875664e-02]

// T2V 14B (wan21_14b)
[-3.03318725e+05, 4.90537029e+04, -2.65530556e+03, 5.87365115e+01, -3.15583525e-01]

// Wan 2.2 5B (wan22_5b) — MISSING
nil
```

### Wan 2.1 / 2.2 I2V Models (inpainting modifier)

```swift
// HNE I2V A14B (wan21_14b, modifier: .inpainting)
[2.57151496e+05, -3.54229917e+04, 1.40286849e+03, -1.35890334e+01, 1.32517977e-01]

// LNE I2V A14B (wan21_14b, modifier: .inpainting)
[2.57151496e+05, -3.54229917e+04, 1.40286849e+03, -1.35890334e+01, 1.32517977e-01]

// Fun Inpainting 14B (wan21_14b, clipEncoder present)
[8.10705460e+03, 2.13393892e+03, -3.72934672e+02, 1.66203073e+01, -4.17769401e-02]
```

---

## Engineering Blog Insights

From Draw Things engineering blog:

### Activation Scaling for FP16

Problem: FP16 overflow during attention computation. Solution: Scale activations by a constant before matmul, unscale after. This allows running 14B models in FP16 without precision loss.

### Video VAE Optimization

Problem: 3D causal convolutions are expensive. Solution: Replace zero-padded 3D conv with equivalent 2D conv on individual frames. Saves memory and compute for video VAE decoding.

### Timestep-based AdaLN Caching

Problem: Adaptive Layer Normalization computed redundantly. Solution: Cache AdaLN parameters when timestep embedding doesn't change significantly between frames. Related to but separate from TeaCache.

### FlashAttention v2.5

Metal-optimized multi-head attention. Key optimization: tiled matrix multiply with shared memory, avoiding full attention matrix materialization. Enables attention over long sequences without quadratic memory.

---

## Scripting Bridge Architecture

### JavaScript API Flow

```
User Script (JavaScript)
    ↓
JavaScriptCore (JSContext)
    ↓
ScriptExecutor (Swift)
    ↓
├── canvas → CanvasWrapper → Metal rendering
├── pipeline → PipelineWrapper → SwiftDiffusion inference
├── filesystem → FileSystemWrapper → sandboxed I/O
└── requestFromUser → UIBuilder → native macOS widgets
```

### Key Implementation Files

- `Libraries/Scripting/Sources/` — JS bridge layer
- JavaScriptCore QoS: user-interactive (highest priority)
- Thread: dedicated `com.draw-things.script` dispatch queue
- One-shot execution model (create new ScriptExecutor per run)

---

## Optimization Opportunities Beyond TeaCache

### 1. VAE Frame Batching

Current: WanVAE processes frames sequentially
Potential: Batch adjacent frames for better GPU utilization
Files: `WanVAE.swift`
Impact: ~5-10% on VAE decode (30s → ~25s for 33 frames)

### 2. Attention Window Tuning

Current: Causal inference uses default window sizes
Potential: Tune window size per-resolution for optimal compute/quality
Files: `Wan.swift`, `UNetProtocol.swift`
Impact: Unknown, needs profiling

### 3. CFG Scheduling

Current: Constant CFG scale throughout generation
Potential: Start high CFG, decay toward end (less compute on late steps)
Files: `DDIMSampler.swift`
Impact: Minor quality improvement at same compute

### 4. Adaptive Step Count

Current: Fixed step count
Potential: Monitor convergence, stop early if latent is stable
Files: `DDIMSampler.swift`
Impact: Variable, depends on content

### 5. Memory-Optimized Refiner Switching

Current: Full model swap at refiner boundary
Potential: Keep shared layers, only swap unique weights
Files: `UNetProtocol.swift`
Impact: Faster refiner switch time (~2-5s savings)
