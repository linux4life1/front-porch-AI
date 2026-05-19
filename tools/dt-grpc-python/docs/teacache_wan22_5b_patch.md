# TeaCache Patch for Wan 2.2 5B (`.wan22_5b`)

> Exact Swift source changes to enable TeaCache for the Wan 2.2 TI2V 5B model in Draw Things.
> For PR submission to [draw-things-community](https://github.com/drawthingsai/draw-things-community).

**Status:** Ready to implement
**Impact:** ~15-20% speedup for Wan 2.2 5B model
**Risk:** Low (follows exact pattern of existing `.wan21_14b` TeaCache integration)

---

## Background

The Wan 2.2 A14B models already have TeaCache support because they use `version: .wan21_14b`. Only the 5B model (`version: .wan22_5b`) is missing it because:

1. `teaCacheCoefficients: nil` in ModelZoo.swift
2. `fatalError()` in TeaCache.swift `compile()` method for `.wan22_5b`
3. No TeaCache creation block in UNetProtocol.swift for `.wan22_5b`

All other TeaCache paths (shouldUseCacheForTimeEmbedding, callAsFunction, denoising loop) already handle `.wan22_5b` correctly.

---

## Change 1: ModelZoo.swift — Add Polynomial Coefficients

**File:** `Libraries/ModelZoo/Sources/ModelZoo.swift`

### Line 1337 (Wan 2.2 TI2V 5B, full precision)

```diff
-      teaCacheCoefficients: nil, framesPerSecond: 24,
+      teaCacheCoefficients: [
+        -5.21862437e+04, 9.23041404e+03, -5.28275948e+02, 1.36987616e+01, -4.99875664e-02,
+      ], framesPerSecond: 24,
```

### Line 1347 (Wan 2.2 TI2V 5B, SVDQuant)

```diff
-      teaCacheCoefficients: nil, framesPerSecond: 24,
+      teaCacheCoefficients: [
+        -5.21862437e+04, 9.23041404e+03, -5.28275948e+02, 1.36987616e+01, -4.99875664e-02,
+      ], framesPerSecond: 24,
```

**Note:** These coefficients are borrowed from Wan 2.1 1.3B (`wan21_1_3b`) as a starting point since both are smaller models (1.3B and 5B) with fewer layers. Ideally they should be recalibrated empirically on Wan 2.2 5B by:
1. Running the model normally for N reference videos
2. Recording the normalized L1-distance between time embeddings at each step
3. Fitting a 4th-degree polynomial to the distance-vs-quality curve

---

## Change 2: TeaCache.swift — Add Compile Case

**File:** `Libraries/SwiftDiffusion/Sources/TeaCache/TeaCache.swift`

### Lines 131-166 — Move `.wan22_5b` from fatalError to compile case

Current code (lines 131-166):
```swift
  public func compile(model: ModelBuilderOrModel, inputs: [DynamicGraph.AnyTensor]) {
    switch modelVersion {
    case .v1, .v2, .kandinsky21, .sdxlBase, .sdxlRefiner, .ssd1b, .svdI2v, .wurstchenStageC,
      .wurstchenStageB, .sd3, .pixart, .auraflow, .sd3Large, .qwenImage, .wan22_5b, .zImage, .flux2,
      .flux2_9b, .flux2_4b, .ltx2:
      fatalError()
    case .hunyuanVideo:
      ...
    case .wan21_1_3b, .wan21_14b:
      reducedModel.compile(inputs: [
        inputs[0], inputs[0], inputs[inputs.count - 2], inputs[inputs.count - 1],
      ])
    }
  }
```

**Change:**
```diff
    case .v1, .v2, .kandinsky21, .sdxlBase, .sdxlRefiner, .ssd1b, .svdI2v, .wurstchenStageC,
-      .wurstchenStageB, .sd3, .pixart, .auraflow, .sd3Large, .qwenImage, .wan22_5b, .zImage, .flux2,
+      .wurstchenStageB, .sd3, .pixart, .auraflow, .sd3Large, .qwenImage, .zImage, .flux2,
      .flux2_9b, .flux2_4b, .ltx2:
      fatalError()
    ...
-    case .wan21_1_3b, .wan21_14b:
+    case .wan21_1_3b, .wan21_14b, .wan22_5b:
      reducedModel.compile(inputs: [
        inputs[0], inputs[0], inputs[inputs.count - 2], inputs[inputs.count - 1],
      ])
```

This is safe because Wan 2.2 5B uses the same shift/scale pattern (last 2 inputs) as Wan 2.1.

---

## Change 3: UNetProtocol.swift — Add TeaCache Creation

**File:** `Libraries/SwiftDiffusion/Sources/Models/UNetProtocol.swift`

### Lines 1073-1104 — Add TeaCache to `.wan22_5b` case

Current code:
```swift
    case .wan22_5b:
      tiledWidth = ...
      tiledHeight = ...
      tileScaleFactor = 4
      let textLength = c[7].shape[1]
      didRunLoRASeparately = ...
      if didRunLoRASeparately {
        let keys = LoRALoader.keys(graph, of: lora.map { $0.file }, modelFile: filePath)
        configuration.keys = keys
        unet = ModelBuilderOrModel.model(
          LoRAWan(
            channels: 3_072, layers: 30, vaceLayers: [], intermediateSize: 14_336,
            time: isCfgEnabled ? batchSize / 2 : batchSize, height: tiledHeight, width: tiledWidth,
            textLength: textLength, causalInference: causalInference, injectImage: false,
            usesFlashAttention: usesFlashAttention, outputResidual: false,
            inputResidual: false, outputChannels: 48, LoRAConfiguration: configuration
          ).1)
      } else {
        unet = ModelBuilderOrModel.model(
          Wan(
            channels: 3_072, layers: 30, vaceLayers: [], intermediateSize: 14_336,
            time: isCfgEnabled ? batchSize / 2 : batchSize, height: tiledHeight, width: tiledWidth,
            textLength: textLength, causalInference: causalInference, injectImage: false,
            usesFlashAttention: usesFlashAttention, outputResidual: false,
            inputResidual: false, outputChannels: 48
          ).1)
      }
```

**Change:** Replace `outputResidual: false` with `outputResidual: isTeaCacheEnabled` and add TeaCache creation blocks:

```swift
    case .wan22_5b:
      tiledWidth =
        tiledDiffusion.isEnabled ? min(tiledDiffusion.tileSize.width * 4, startWidth) : startWidth
      tiledHeight =
        tiledDiffusion.isEnabled
        ? min(tiledDiffusion.tileSize.height * 4, startHeight) : startHeight
      tileScaleFactor = 4
      let textLength = c[7].shape[1]
      didRunLoRASeparately =
        !lora.isEmpty && rankOfLoRA > 0 && !isLoHa && runLoRASeparatelyIsPreferred
        && canRunLoRASeparately
      if didRunLoRASeparately {
        let keys = LoRALoader.keys(graph, of: lora.map { $0.file }, modelFile: filePath)
        configuration.keys = keys
        unet = ModelBuilderOrModel.model(
          LoRAWan(
            channels: 3_072, layers: 30, vaceLayers: [], intermediateSize: 14_336,
            time: isCfgEnabled ? batchSize / 2 : batchSize, height: tiledHeight, width: tiledWidth,
            textLength: textLength, causalInference: causalInference, injectImage: false,
            usesFlashAttention: usesFlashAttention, outputResidual: isTeaCacheEnabled,
            inputResidual: false, outputChannels: 48, LoRAConfiguration: configuration
          ).1)
        if isTeaCacheEnabled {
          teaCache = TeaCache(
            modelVersion: version, coefficients: teaCacheConfiguration.coefficients,
            threshold: teaCacheConfiguration.threshold, steps: teaCacheConfiguration.steps,
            maxSkipSteps: teaCacheConfiguration.maxSkipSteps,
            reducedModel: LoRAWan(
              channels: 3_072, layers: 0, vaceLayers: [], intermediateSize: 14_336,
              time: isCfgEnabled ? batchSize / 2 : batchSize, height: tiledHeight,
              width: tiledWidth, textLength: textLength, causalInference: causalInference,
              injectImage: false,
              usesFlashAttention: usesFlashAttention, outputResidual: false, inputResidual: true,
              outputChannels: 48, LoRAConfiguration: configuration
            ).1)
        }
      } else {
        unet = ModelBuilderOrModel.model(
          Wan(
            channels: 3_072, layers: 30, vaceLayers: [], intermediateSize: 14_336,
            time: isCfgEnabled ? batchSize / 2 : batchSize, height: tiledHeight, width: tiledWidth,
            textLength: textLength, causalInference: causalInference, injectImage: false,
            usesFlashAttention: usesFlashAttention, outputResidual: isTeaCacheEnabled,
            inputResidual: false, outputChannels: 48
          ).1)
        if isTeaCacheEnabled {
          teaCache = TeaCache(
            modelVersion: version, coefficients: teaCacheConfiguration.coefficients,
            threshold: teaCacheConfiguration.threshold, steps: teaCacheConfiguration.steps,
            maxSkipSteps: teaCacheConfiguration.maxSkipSteps,
            reducedModel: Wan(
              channels: 3_072, layers: 0, vaceLayers: [], intermediateSize: 14_336,
              time: isCfgEnabled ? batchSize / 2 : batchSize, height: tiledHeight,
              width: tiledWidth, textLength: textLength, causalInference: causalInference,
              injectImage: false, usesFlashAttention: usesFlashAttention,
              outputResidual: false, inputResidual: true, outputChannels: 48
            ).1)
        }
      }
```

Key differences from `.wan21_14b`:
- `channels: 3_072` (not 5_120)
- `layers: 30` for full model, `layers: 0` for reduced model (same pattern)
- `intermediateSize: 14_336` (not 13_824)
- `outputChannels: 48` (not 16)
- No `vaceLayers` or `injectImage` logic (5B is simpler)

---

## No Changes Needed

These paths already handle `.wan22_5b` correctly:

1. **TeaCache.swift:78-81** (`shouldUseCacheForTimeEmbedding`): `.wan22_5b` is in the `fatalError()` list BUT this is inside `if let inferModel = inferModel`. Since we create TeaCache with `inferModel: nil`, this path is never reached. **No change needed.**

2. **TeaCache.swift:196-200** (`callAsFunction`): `.wan22_5b` is already in the correct case that reads shift/scale from `restInputs[restInputs.count - 2]` and `restInputs[restInputs.count - 1]`. **No change needed.**

3. **UNetProtocol.swift:2536-2650** (denoising loop): Already handles `.wan22_5b` alongside `.wan21_1_3b` and `.wan21_14b` for the full TeaCache check/cache/skip flow. **No change needed.**

4. **UNetProtocol.swift:2151** (compile): Already calls `teaCache?.compile(model: unet, inputs: inputs)` for `.wan22_5b`. **No change needed** (but requires Change 2 above to not fatalError).

---

## Verification

After applying changes, build and test:

```bash
cd draw-things-community
bazel build Apps:gRPCServerCLI-macOS --config=release
```

Test with:
1. Generate a reference video with TeaCache disabled
2. Generate with TeaCache enabled (threshold=0.15, maxSkipSteps=3)
3. Compare visual quality — should be very similar
4. Compare timing — should be ~15-20% faster

---

## PR Checklist

- [ ] ModelZoo.swift: Add coefficients for both 5B entries (lines 1337, 1347)
- [ ] TeaCache.swift: Move `.wan22_5b` from fatalError to compile case (line 133)
- [ ] UNetProtocol.swift: Add TeaCache creation in `.wan22_5b` case (lines 1073-1104)
- [ ] Build passes: `bazel build Apps:gRPCServerCLI-macOS`
- [ ] Visual quality acceptable with threshold=0.15
- [ ] Timing shows improvement (~15-20%)
- [ ] Optional: Recalibrate polynomial coefficients on Wan 2.2 5B specifically
