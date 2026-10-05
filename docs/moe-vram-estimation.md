# MoE-Aware VRAM Estimation and KoboldCPP Launch for Auto-Configure

> **Status (2026-10-04).** The estimation on this page is live, in the form
> "How the estimate is worked out now" describes. The preset editor, the
> Local model card and every launch fit the model with `KoboldFit`, which
> runs `koboldLoad` (`lib/utils/kobold_placement.dart`) over the model file's
> own header (`GGUFModelInfo`, `GGUFWeights`).
> `VramEstimator.estimateFromArchitecture` is kept for the tests that check
> those figures against real KoboldCpp loads. What the rest of this page
> calls the active weight ratio (the `activeWeightRatio` getter), the batch
> suggestion (`suggestBatchSize`) and the fixed overhead are gone; the one
> piece of the ratio still used is the fallback for a file whose tensor
> table cannot be read (`gpuWeightRatioWhenOffloadingExperts`).
>
> **What the estimate is for.** It does not decide how a model is loaded,
> and never did: KoboldCpp fits the model. The estimate is a guess at how
> that fit will come out, there so you can pick a context size, batch size
> and cache type that fit in the graphics memory left over after a MoE
> model's active weights, and the model runs at full speed. The preset the
> dialog writes tells KoboldCpp to fit the model and to keep the spare
> memory the guess counted on.
>
> **What is gone.** Only the Auto-Configure button and the code behind it
> (`KoboldLayerSolver`, `OptimizationService`), which picked a GPU layer
> count for launches that used no preset. Those launches now leave the fit
> to KoboldCpp as well (Settings → Hardware & GPU → Graphics memory:
> Automatic). Parts 3 to 6 of "Required Code Changes" below describe that
> removed code, and the `activeWeightRatio` getter of part 1 is removed
> too; they are kept for the history. The launch design is in
> [design/kobold-launch-rewrite.md](design/kobold-launch-rewrite.md).

## How the estimate is worked out now (2026-10-04)

The figures are now read from the model file and KoboldCpp's own rules,
and checked against what a real KoboldCpp printed: 93 loads of 20 models
on Apple Silicon, loads of three models on a 16 GB AMD card (Vulkan and
ROCm), and the original author's log from a 6 GB NVIDIA card. The code is
`lib/utils/kobold_memory_rules.dart`; the measurements are pinned in
`test/utils/vram_estimator_real_engine_test.dart`,
`test/utils/vram_estimator_metal_test.dart` and
`test/fixtures/kobold_loads/`.

| Part | How it is worked out | How close it came |
|---|---|---|
| Weights on the card | The sizes of the file's own tensors (the tensor table in the header), sorted by where KoboldCpp puts them: the blocks, the experts (kept in system memory when they do not fit), the output layer. A model that ties its output to its input embedding gets a second copy on the card. On Apple Silicon the whole file is mapped. | To the MiB (784.42 reported, 784 worked out, for MoE experts kept off the card; 6776.84 for Gemma 4 12B with its tied copy) |
| Attention cache | Per layer: keys and values for the context plus 128 cells, rounded up to 256. A sliding-window layer with sliding window on holds the window plus one batch, rounded up to 256, plus 128. Recurrent and convolution layers keep a small fixed state instead; layers that reuse another layer's cache keep none; compressed-attention (MLA) models keep one key row per layer. With flash attention off, every layer's values are sized to the largest layer's. | To the MiB on every load |
| Working memory | The larger of: the scores for a batch over the whole vocabulary; the layers' working set (masks over the cache, the feed-forward block, the attention queries; with flash attention off, one layer's attention scores). On Vulkan, once the scores reach 1 GiB they add to the layers' set instead. On Apple Silicon, long contexts need extra room. | Never below the engine; 8.5% above on average on Apple Silicon |
| Beyond the listed buffers | Vulkan 80 MB, ROCm 330 to 530 MB, NVIDIA 500 MB (no measurement yet), Apple Silicon 100 MB. | Measured on Vulkan and ROCm |

The active weight ratio below was the original way of working out a MoE
model's share on the card, from its parameter counts. It came close for
some models and not others (Gemma 4 26B-A4B: about 12% against 11.1%
exactly; Kimi-VL-A3B: about 22% against 5.4%), because the parameter
counts leave out what the file stores at different precisions. The tensor
table gives the exact answer, so the ratio is now only the fallback for a
file whose tensor table cannot be read.

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
