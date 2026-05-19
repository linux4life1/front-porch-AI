# Draw Things JavaScript Scripting API Reference

> Complete reference for the Draw Things scripting API (JavaScriptCore bridge).
> Extracted from draw-things-community source analysis, 2026-02-07.

---

## Architecture

- **Engine:** JavaScriptCore (native macOS/iOS)
- **Thread:** Runs on `com.draw-things.script` dispatch queue (user-interactive QoS)
- **Execution:** Synchronous — all API calls block; JS runs on same thread as generation
- **Lifecycle:** Each `ScriptExecutor` instance can only run once; create new for each script
- **Error handling:** Swift exceptions propagate as JS exceptions

---

## Global Objects

### `pipeline`

Controls model loading and image generation.

```javascript
// Get current configuration (read/write)
const config = pipeline.configuration;

// Run generation (BLOCKING — returns when complete)
pipeline.run({
  configuration: config,
  prompt: "your prompt here",
  negativePrompt: "blurry, low quality",
  mask: maskObject  // optional, for inpainting
});

// Model management
pipeline.findLoRAByName("lora_name");              // Load LoRA by name
pipeline.findControlByName("control_name");        // Load ControlNet by name
pipeline.areModelsDownloaded(["model.ckpt"]);      // Check availability
pipeline.downloadBuiltins(["model.ckpt"]);         // Auto-download from registry
```

### `canvas`

Controls the drawing canvas, layers, and image I/O.

```javascript
// Canvas operations
canvas.clear();
canvas.canvasZoom;                    // get/set zoom level
canvas.moveCanvas(x, y);             // pan
canvas.updateCanvasSize(config);      // resize to config dimensions
canvas.boundingBox();                 // { origin: {x,y}, size: {w,h} }
canvas.topLeftCorner();               // { x, y }

// Image I/O
canvas.loadImage(filePath);           // Load from file path
canvas.loadImageSrc(base64OrDataUrl); // Load from data URL
canvas.saveImage(filePath, visibleRegionOnly);  // Save to file
canvas.saveImageSrc(visibleRegionOnly);         // Get as base64

// Layer loading
canvas.loadMaskFromPhotos();
canvas.loadDepthMapFromPhotos();
canvas.loadScribbleFromPhotos();
canvas.loadPoseFromPhotos();
canvas.loadColorFromPhotos();
canvas.loadCustomFromPhotos();        // Custom layer (used in FLF2V)
canvas.loadCustomFromSrc(base64);     // Custom layer from data
canvas.addToMoodboardFromPhotos();
canvas.addToMoodboardFromSrc(base64);

// Mask operations
const mask = canvas.createMask(width, height, MaskValueType.MASK);
mask.fillRectangle(x, y, width, height, fillValue);
canvas.currentMask();                 // Current mask
canvas.foregroundMask();              // Auto-detect foreground
canvas.backgroundMask();             // Auto-detect background
canvas.bodyMask(["upper_body", "neck"], extraArea);

// Detection
const faces = canvas.detectFaces();   // [{ origin: {x,y}, size: {w,h} }]
const hands = canvas.detectHands();
canvas.moveCanvasToRect(faces[0]);    // Move canvas to detection

// AI features
const embeddings = canvas.CLIP(["prompt1", "prompt2"]); // CLIP embeddings
const answer = canvas.answer("qwen3-7b", "question");   // Local LLM inference

// Moodboard
canvas.clearMoodboard();
canvas.removeFromMoodboardAt(index);
canvas.setMoodboardImageWeight(weight, index);
```

### `filesystem`

File system access (read-only for most operations).

```javascript
filesystem.pictures.path;                    // Pictures directory path
filesystem.pictures.readEntries("subfolder"); // List files
filesystem.readEntries(dirPath);             // List arbitrary directory
```

### `console`

Standard console logging.

```javascript
console.log("message");
console.repl();         // Drop into interactive REPL
```

---

## Configuration Object

All generation parameters are accessible via `pipeline.configuration`:

### Core Parameters

```javascript
const config = pipeline.configuration;

config.model = "model_name.ckpt";          // Base model
config.refinerModel = "refiner.ckpt";      // Refiner model (or "" for none)
config.refinerStart = 0.1;                 // When to switch to refiner (0-1)
config.steps = 25;                         // Total denoising steps
config.guidanceScale = 3.5;               // CFG scale
config.seed = -1;                          // Seed (-1 = random)
config.seedMode = 2;                       // 0=deterministic, 1=scale-alike, 2=random
config.sampler = 17;                       // Sampler type (see table below)
config.width = 448;                        // Output width (divisible by 64)
config.height = 832;                       // Output height (divisible by 64)
config.strength = 1.0;                     // Denoising strength (inpainting)
config.shift = 5.0;                        // Shift parameter
config.batchCount = 1;                     // Number of batches
config.batchSize = 1;                      // Images per batch (max 4)
```

### Video / I2V Parameters

```javascript
config.numFrames = 33;                     // Number of video frames
config.fps = 16;                           // Frames per second
config.motionScale = 127;                  // Motion bucket ID
config.guidingFrameNoise = 0.0;           // Conditional augmentation
config.startFrameGuidance = 1.0;          // First frame guidance
```

### TeaCache Parameters

```javascript
config.teaCache = true;                    // Enable TeaCache
config.teaCacheStart = 2;                 // Start at step N
config.teaCacheEnd = 23;                  // End at step N
config.teaCacheThreshold = 0.15;          // Skip threshold (0-1)
config.teaCacheMaxSkipSteps = 3;          // Max consecutive skips
```

### LoRA Configuration

```javascript
config.loras = [
  {
    file: "lora_name.ckpt",
    weight: 0.8,
    mode: "base"   // "all" | "base" | "refiner"
  },
  {
    file: "another_lora.ckpt",
    weight: 1.0,
    mode: "refiner"
  }
];
```

### ControlNet Configuration

```javascript
config.controls = [
  {
    file: "control_model.ckpt",
    weight: 1.0,
    guidanceStart: 0.0,
    guidanceEnd: 1.0,
    controlImportance: "balanced",  // "balanced" | "prompt" | "control"
    noPrompt: false,
    globalAveragePooling: false,
    downSamplingRate: 1.0,
    inputOverride: "unspecified",
    targetBlocks: []
  }
];
```

### Refiner Parameters

```javascript
config.refinerModel = "refiner.ckpt";
config.refinerStart = 0.1;                // Switchover point (0-1)
config.stage2Steps = 10;                  // Refiner-specific steps
config.stage2Cfg = 5.0;                   // Refiner guidance
config.stage2Shift = 1.0;                // Refiner shift
```

### Advanced Sampling

```javascript
config.clipSkip = 0;                      // Skip N CLIP layers
config.clipWeight = 1.0;                  // CLIP vs other encoder balance
config.stochasticSamplingGamma = 0.0;    // Stochastic sampler param
config.cfgZeroStar = false;              // CFG-Zero* optimization
config.cfgZeroInitSteps = 0;            // CFG warm-up steps
config.speedUpWithGuidanceEmbed = false; // Guidance embedding
config.resolutionDependentShift = false; // Resolution-aware shift
config.preserveOriginalAfterInpaint = true;
```

### Text Encoder Control

```javascript
config.t5TextEncoder = false;             // Use T5 instead of CLIP
config.separateClipL = false;            // Separate CLIP-L encoder
config.separateOpenClipG = false;        // Separate OpenCLIP-G encoder
config.separateT5 = false;              // Separate T5 encoder
config.clipLText = "";                   // CLIP-L specific prompt
config.openClipGText = "";              // OpenCLIP-G specific prompt
config.t5Text = "";                      // T5 specific prompt
config.negativePromptForImagePrior = false;
config.imagePriorSteps = 25;
```

### Tiled Generation

```javascript
config.tiledDiffusion = false;            // Enable spatial tiling
config.diffusionTileWidth = 96;
config.diffusionTileHeight = 96;
config.diffusionTileOverlap = 4;
config.tiledDecoding = false;            // VAE tiling
config.decodingTileWidth = 64;
config.decodingTileHeight = 64;
config.decodingTileOverlap = 4;
```

### Upscaling / Hires Fix

```javascript
config.upscaler = "";                     // Upscaler model
config.upscalerScaleFactor = 2;          // 2x, 4x, etc.
config.hiresFix = false;                 // Enable hires fix
config.hiresFixWidth = 0;
config.hiresFixHeight = 0;
config.hiresFixStrength = 0.7;
```

---

## Sampler Types

| Value | Name | Notes |
|---|---|---|
| 0 | DDIM | Classic |
| 1 | PLMS | |
| 2 | Euler | |
| 3 | Euler Ancestral | Stochastic |
| 4 | DPM++ 2M Karras | |
| 5 | DPM++ SDE Karras | |
| 6 | UniPC | |
| 7 | LCM | Latent Consistency |
| 8 | TCD | |
| 9 | Euler A Sub-step | |
| 10 | DPM++ 2M SDE | |
| 11 | DPM++ 2M AYS | |
| 12 | DPM++ SDE Sub-step | |
| 13 | Euler Flow | |
| 14 | DPM++ 2M Discrete Flow | |
| 15 | Euler SMEA | |
| 16 | DDIM Trailing | Recommended for Wan |
| 17 | DDIM (variant) | Used in configs |

---

## User Interaction (UI Widgets)

```javascript
const result = requestFromUser("Title", "Confirm Button", function() {
  return [
    this.section("Section Name", "Description", [
      this.slider(defaultVal, this.slider.fractional(decimals), min, max, "label"),
      this.textField(defaultVal, "placeholder", multiline, height),
      this.imageField("label", multiSelect),
      this.comboBox(selectedIndex, ["option1", "option2"]),
      this.segmented(selectedIndex, ["opt1", "opt2"]),
      this.size(width, height, minVal, maxVal),
      this.switch(isOn, "label"),
      this.directory(),
      this.plainText("text"),
      this.markdown("**bold** text"),
      this.image(src, height, selectable)
    ])
  ];
});
// result = [[section0_widget0_value, section0_widget1_value], [section1_widget0_value], ...]
```

---

## Timing

```javascript
const startTime = new Date().getTime();
pipeline.run({ configuration: config, prompt: prompt });
const endTime = new Date().getTime();
const elapsedMs = endTime - startTime;
```

**No internal timing available** — only wall-clock time via `Date.now()`.

---

## Limitations

| Feature | Status | Notes |
|---|---|---|
| Per-step progress | NOT available | `pipeline.run()` is blocking |
| Interrupt/Cancel | NOT available | Must wait for completion |
| Per-frame video control | NOT available | Can't modify frame conditioning |
| GPU memory control | NOT available | Can't override dtypes |
| FP8/quantization control | NOT available | Uses model's default |
| Network access | NOT available | Local file I/O only |
| Real-time streaming | NOT available | Save to disk only |
| Script-to-script communication | NOT available | Each script isolated |

---

## Patterns

### Batch Generation Loop

```javascript
for (let i = 0; i < numGenerations; i++) {
  config.seed = -1;  // Randomize each
  pipeline.run({ configuration: config, prompt: prompt });
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
  canvas.saveImage(outputPath + "/batch_" + timestamp + ".png", true);
}
```

### Dynamic Resolution

```javascript
const targetPixels = 448 * 832;  // ~372k pixels
const aspectRatio = sourceWidth / sourceHeight;
config.width = Math.floor(Math.sqrt(targetPixels * aspectRatio) / 64) * 64;
config.height = Math.floor(Math.sqrt(targetPixels / aspectRatio) / 64) * 64;
```

### A/B Config Testing

```javascript
const configs = [
  { steps: 20, teaCache: true, teaCacheThreshold: 0.1, label: "conservative" },
  { steps: 20, teaCache: true, teaCacheThreshold: 0.2, label: "balanced" },
  { steps: 20, teaCache: true, teaCacheThreshold: 0.3, label: "aggressive" },
];

for (const c of configs) {
  config.steps = c.steps;
  config.teaCache = c.teaCache;
  config.teaCacheThreshold = c.teaCacheThreshold;
  config.seed = 42;  // Same seed for comparison

  const start = Date.now();
  pipeline.run({ configuration: config, prompt: prompt });
  const elapsed = Math.round((Date.now() - start) / 1000);

  canvas.saveImage(outputPath + "/" + c.label + ".png", true);
  console.log(c.label + ": " + elapsed + "s");
}
```
