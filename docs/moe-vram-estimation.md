# MoE-Aware VRAM Estimation and KoboldCPP Launch for Auto-Configure

## Problem

The current app has two interacting failures for MoE models:

1. **VRAM over-estimation**: `KoboldLayerSolver` assumes all weights per
   transformer layer must reside in GPU VRAM. For MoE models this overestimates
   VRAM requirements by 4–20×: only `expert_used_count` out of `expert_count`
   expert FFN sub-layers are active during inference. The inactive experts can
   stay in system RAM.

2. **Memory doubling on launch**: The app launches KoboldCPP with `--gpulayers N`
   and `--usemlock` (default ON) without `--moecpu`. KoboldCPP copies ALL
   weights for those N layers to GPU (including all expert FFNs), while mmap'd
   pages for the same weights stay pinned in RAM by `--usemlock`. For a 13.27 GB
   Gemma4 model on a 6 GB card, this causes ~35 GB total memory usage, heavy
   swapping, and 0.2 t/s.

### Root cause of memory doubling

Traced from `koboldcpp` source:

- KoboldCPP defaults to **mmap** enabled. The entire GGUF file is mapped into
  CPU virtual address space.
- `--gpulayers N` transfers tensor data to GPU VRAM but the mmap'd pages
  **remain mapped** in CPU address space. They are not unmapped after transfer
  (only marginal padding/metadata pages get unmapped).
- `--usemlock` pins ALL mmap'd pages in physical RAM via `mlockall()` /
  `VirtualLock()`. This prevents the OS from evicting the GPU-offloaded weight
  pages under memory pressure.
- **Result**: every offloaded MoE layer occupies ~442 MB in VRAM AND ~442 MB
  pinned in RAM = double allocation.

### Why KoboldCPP's kcpps/autofit path works

The kcpps preset path passes only `--config`, `--port`, and optionally `--model`.
No `--gpulayers`, no `--usemlock`, and KoboldCPP's internal autofit (enabled by
default when `--gpulayers` is unset or `-1`) uses a **MoE-aware two-phase
fitting algorithm** (`common/fit.cpp:504-617`):

**Phase 1** — Regex tensor overrides force ALL expert weights to CPU:
```
blk\.\d+\.ffn_(up|down|gate|gate_up)_(ch|)exps=CPU
```
Only attention + shared FFN + router weights are placed on GPU. This is
controlled by `--moecpu` (default: 0 = off; pass without value = 999 = all
layers keep experts on CPU).

**Phase 2** — If there's surplus VRAM after phase 1, convert some layers to
full offload (including experts) front-to-back, also trying partial layer
fractions (ATTN only, UP/GATE fractions).

The fitting algorithm also automatically disables repacking when mmap is on
(`kcpp_permit_any_repack = false` in `repack.cpp:2974`), avoiding a second
CPU-side copy.

## Detecting MoE from GGUF Metadata

Standard GGUF keys distinguish MoE from dense architectures:

| Key | Example (Gemma4) | Example (Qwen3.6-35B-A3B) |
|-----|:-:|:-:|
| `{arch}.expert_count` | 128 | 256 |
| `{arch}.expert_used_count` | 8 | 8 |
| `{arch}.expert_feed_forward_length` | 704 | 512 |
| `{arch}.expert_shared_feed_forward_length` | — | 512 |
| `{arch}.feed_forward_length` | 2112 | — |

When `expert_count > 1`, the model is MoE.

## Active Weight Ratio

For each transformer layer, estimate parameter counts using GGUF architecture
metadata. This tells us how much weight actually needs GPU VRAM when
`--moecpu` is active (experts stay on CPU):

```
attnParams  = 2 × nEmbd² × (1 + nKvHeads/nHeads)   # Q/K/V/O
denseFfn    = 3 × nEmbd × ffnDim                     # shared FFN (0 if absent)
sharedExp   = 3 × nEmbd × expertSharedFfnDim         # shared expert (0 if absent)
router      = nEmbd × expertCount                     # router/gate
expertFfn   = 3 × nEmbd × expertFfnDim                # per routed expert

totalPerLayer = attnParams + denseFfn + sharedExp + router
                + expertCount × expertFfn

activePerLayer = attnParams + denseFfn + sharedExp + router
                 + expertUsedCount × expertFfn

activeWeightRatio = activePerLayer / totalPerLayer
```

For dense models (no `expert_count`): `activeWeightRatio = 1.0`.

### Expected ratios (computed from real GGUF metadata)

| Model | Block | Embd | ffnDim | Exp | Used | ExpFFN | Active ratio | Claimed |
|-------|:----:|:----:|:------:|:---:|:----:|:------:|:-----------:|:-------:|
| Gemma4-26B-A4B | 30 | 2816 | 2112 | 128 | 8 | 704 | ~12% | A4B |
| Qwen3.6-35B-A3B | 40 | 2048 | — | 256 | 8 | 512 | ~6% | A3B |
| Kimi-VL-A3B | 27 | 2048 | 11264 | 64 | 6 | 1408 | ~22% | A3B |
| LFM2.5-8B-A1B | 24 | 2048 | 7168 | 32 | 4 | 1792 | ~25% | A1B |
| Dense (any) | — | — | — | 0 | — | — | 100% | — |

Implementation note: the ratio is a *parameter count ratio*. Since quantization
applies uniformly to all weight tensors in the file, the byte ratio ≈ parameter
ratio. This makes the ratio quantization-independent — it applies equally to
Q4_K_M, Q6_K, etc.

### What this means for `--gpulayers`

With `--moecpu`, each offloaded layer only consumes `bytesPerLayer ×
activeWeightRatio` of VRAM. For Gemma4: ~442 MB × 0.12 ≈ **54 MB per layer**.
All 30 layers: ~1.6 GB for weights + KV cache + batch buffers comfortably fits
in 6 GB VRAM.

## Batch-Size-Aware Overhead

The solver's fixed 1200 MB overhead should be replaced with:

```
overheadMb = fixedBase + batchSize × perTokenBatchOverhead / (1024 × 1024)
```

Where:

```
perTokenBatchOverhead = nVocab × 2          # logits buffer (FP16)
                        + nEmbd × 8         # attention intermediates
                        + ffnDimEffective × 4 # FFN intermediates

fixedBase ≈ 600                             # graph, CUDA context, scratch
```

When `nVocab` is not yet parsed, estimate it from model size tier:
- <3B params: 32K
- 3–15B: 128K
- >15B: 256K

The `ffnDimEffective` is `expertFfnDim` for MoE models (active expert buffers
only), or `feed_forward_length` for dense models.

### Calibration point

At batch=512 with default settings:
`overheadMb = 600 + 512 × (262144×2 + 2816×8 + 704×4) / 1M ≈ 1200` ✓

| Batch | Overhead (Gemma4 vocab=262K) | Notes |
|:-----:|:----------------------------:|-------|
| 256 | ~900 MB | Lower than default |
| 512 | ~1200 MB | Default — matches current |
| 1024 | ~1800 MB | Fits 6GB card (user-verified) |
| 2048 | ~2700 MB | Needs 8GB+ card |
| 4096 | ~4400 MB | Needs 12GB+ card |
| 8192 | ~8000 MB | Needs 24GB card |

## Required Code Changes

### 1. `GGUFModelInfo` (`lib/utils/gguf_parser.dart`)

Add fields:
- `int? expertCount`
- `int? expertUsedCount`
- `int? ffnDim` (`{arch}.feed_forward_length`)
- `int? expertFfnDim` (`{arch}.expert_feed_forward_length`)
- `int? expertSharedFfnDim` (`{arch}.expert_shared_feed_forward_length`)
- `int? nVocab` (from `tokenizer.ggml.tokens` array length)
- `int? nHeads`
- `int? nKvHeads`

Add computed getters:
- `bool get isMoe => expertCount != null && expertCount > 1`
- `double get activeWeightRatio` — implements the formula above

### 2. `GGUFParser` (`lib/utils/gguf_parser.dart`)

Add these to the KV whitelist in both `getKvCacheBytesPerToken` and
`getModelArchitectureInfo`:
- `{arch}.expert_count`
- `{arch}.expert_used_count`
- `{arch}.expert_feed_forward_length`
- `{arch}.expert_shared_feed_forward_length`
- `{arch}.feed_forward_length` (already used for non-arch filter, add arch prefix)

Add tokenizer key for vocab size:
- `tokenizer.ggml.tokens` — read array length (this gives `nVocab`)

Handle per-layer `head_count_kv` arrays (Gemma4 stores it as int32 array of
length = block_count). Take the maximum value when an array.

### 3. `KoboldLayerSolver` (`lib/utils/kobold_layer_solver.dart`)

Add parameters:
- `double activeWeightRatio = 1.0`
- `int batchSize = 512`
- `int nVocab = 0`
- `int nEmbd = 0`
- `int ffnDimEffective = 0`

Changes:
- `weightsCost = (bytesPerLayer × mid × activeWeightRatio / 1MB).round()`
- Compute `overheadMb` from batchSize, nVocab, nEmbd, ffnDimEffective
- Update reasoning strings to mention MoE scaling when applicable

### 4. `OptimizationService` (`lib/services/optimization_service.dart`)

Pass batch size and GGUFModelInfo (or at least the relevant fields) through
to the solver. Signature change:

```dart
static OptimizationResult calculateSettings(
  HardwareInfo hardware, {
  int modelSizeMb = 0,
  int? requestedContextSize,
  GGUFModelInfo? modelInfo,     // NEW — replaces kvBytesPerToken
  int kvQuantizationLevel = 0,
  int batchSize = 512,          // NEW — from BackendSettings.blasBatchSize
})
```

### 5. `KoboldService` — KoboldCPP launch arguments
(`lib/services/kobold_service.dart:254-329`)

The direct path needs three changes for MoE models:

**a) Pass `--moecpu` when the model is MoE:**

When `GGUFModelInfo.isMoe` is true, add `--moecpu` (without a value = 999 =
keep all expert weights on CPU):

```dart
// After GPU backend flags, before flash attention:
if (isMoeModel) args.add('--moecpu');
```

This prevents KoboldCPP from transferring expert weights to VRAM. Only
attention + shared FFN + router weights go to GPU.

**b) Don't pass `--usemlock` when MoE + GPU offloading is active:**

`--usemlock` with mmap pins the entire model file in RAM. With `--moecpu`,
the expert weights stay in mmap'd pages and should be swappable — mlock
defeats that. Conditional:

```dart
if (_storageService.mlockEnabled && !isMoeModel) {
  args.add('--usemlock');
}
```

Or more broadly, never pass `--usemlock` when `--gpulayers > 0` (the mlock
comment says "prevents OS from paging model weights to disk under memory
pressure" but GPU-offloaded weights aren't accessed from CPU, and non-offloaded
weights already have mmap demand-paging).

**c) Consider lowering `--gpulayers` to `nLayers` (full offload of non-expert
weights):**

With `--moecpu`, each layer only costs ~54 MB (for Gemma4). All 30 layers =
~1.6 GB. The solver should recommend full layer offload (`gpuLayers = nLayers`)
when `activeWeightRatio × fileSize + contextCost + overheadMb ≤ vramMb`.

### 6. Callers (`settings_page.dart`, `model_settings_dialog.dart`)

- Read `batchSize` from `BackendSettings.blasBatchSize`
- Fetch `GGUFModelInfo` (full model info) from `ModelManager`
  instead of just `kvBytesPerToken`
- Pass both to `OptimizationService.calculateSettings()`

### 7. Fix `mlockEnabled` default (`backend_settings.dart:49-50`)

The current code:
```dart
bool _mlockEnabled =
    !( /* platform default computed at load if needed, but we persist */ false);
```
This evaluates to `true` on all platforms. The comment says "Default ON for
Win/Mac, OFF for Linux" but this is not implemented. Fix:

```dart
bool _mlockEnabled = Platform.isLinux ? false : true;
```

Or simply default to `false` — the memory-doubling risk outweighs the
mid-session paging protection benefit.

## Edge Cases

1. **Head_count_kv as array** (Gemma4): Store per-layer values or take max.
   Fall back to `head_count` if unavailable.

2. **No expert FFN dim** (dense models): `activeWeightRatio = 1.0`,
   `ffnDimEffective = feed_forward_length`.

3. **No feed_forward_length** (MoE-only architectures like some Qwen MoE
   variants): `ffnDimEffective = expertFfnDim × expertUsedCount / expertCount`
   (rough approximation of the active vs total compute ratio).

4. **Shared experts** (DeepSeek/Qwen MoE): Always-active expert treated as
   part of `activePerLayer`, not scaled by `expertUsedCount/expertCount`.

5. **Streaming batch = 1 (decoding)**: The batch size overhead formula above
   is for prefill. Decoding uses batch=1 and consumes minimal temporary VRAM.
   The overhead is pre-allocated by KoboldCPP at the configured batch size,
   so we estimate for the configured value.

6. **Tar-wrapped GGUF files** (`.tar.001` split files): The parser needs a
   512-byte offset before reading GGUF data. This is orthogonal to the MoE
   estimation changes and tracked separately.

## Summary of KoboldCPP flags for MoE models

| Flag | Dense | MoE | Why |
|------|-------|-----|-----|
| `--gpulayers N` | Pass | Pass (with `--moecpu`) | Offload attention + shared FFN to GPU |
| `--moecpu` | Don't pass | **Pass** (no value = all layers) | Keep expert weights on CPU, prevent VRAM/RAM doubling |
| `--usemlock` | Optional | **Don't pass** | Avoid pinning expert weight mmap pages in RAM |
| `--nommap` | Don't pass | Don't pass | mmap + `--moecpu` works correctly; `--nommap` would load all experts into heap |
