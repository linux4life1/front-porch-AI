# Local Image Generation Controls - Feature Plan

## Overview
Expose core Stable Diffusion generation parameters (sampler, steps, CFG, seed) to users for local backends (A1111, Forge, Draw Things) without overwhelming them with advanced options.

---

## Draw Things Compatibility Investigation

### API Compatibility
Draw Things exposes an A1111-compatible HTTP API server that supports:
- ✅ `/sdapi/v1/txt2img` - Text-to-image generation
- ✅ `/sdapi/v1/sd-models` - List checkpoints
- ✅ `/sdapi/v1/options` - Get/set options
- ✅ `/sdapi/v1/samplers` - List available samplers
- ✅ `/sdapi/v1/schedulers` - List available schedulers
- ✅ `/sdapi/v1/loras` - List LoRAs

**Conclusion**: Parameters that work with A1111 will work with Draw Things. No separate API handling needed.

---

## Parameter Selection Strategy

### Tier 1: Always Visible (Core Controls)
Parameters that meaningfully affect output quality/speed and are safe to adjust:

| Parameter | Type | Range | Default | Description |
|-----------|------|-------|---------|-------------|
| **Steps** | Slider | 5–50 | 20 | Quality vs speed tradeoff |
| **CFG Scale** | Slider | 1–20 | 7 | Prompt adherence vs creativity |
| **Sampler** | Dropdown | Dynamic* | Euler a | Noise schedule algorithm |

*Sampler list fetched from `/sdapi/v1/samplers` on Test connection, with fallback hardcoded list.

### Tier 2: Collapsible "Advanced" Section
Parameters that power users might want, hidden by default:

| Parameter | Type | Range | Default | Description |
|-----------|------|-------|---------|-------------|
| **Seed** | TextField + Randomize button | -1 or any int | -1 (random) | Reproducibility control |
| **Batch Size** | Slider | 1–8 | 1 | Images per generation |
| **Scheduler** | Dropdown | Dynamic* | Automatic | Noise scheduler (DDIM, Karras, etc.) |

### Parameters NOT Exposed (Intentionally)
These are either too advanced, rarely useful, or backend-specific:
- `s_churn`, `s_tmin`, `s_tmax`, `s_noise` - DDIM-specific noise parameters (too advanced)
- `eta` - DDIM eta parameter (too advanced)
- `s_min_uncond` - Rarely needed
- `subseed`, `subseed_strength` - Variation seeds (too advanced)
- `seed_resize_from_h/w` - Rarely useful
- `override_settings` - Keep model switching explicit
- `alwayson_scripts` - Script args (too complex for UI)
- `refiner_checkpoint`, `refiner_switch_at` - Refiners (separate feature)
- `hr_` parameters - Hires fix (separate feature)

---

## API Implementation Details

### A1111/Forge API Reference
Endpoint: `POST /sdapi/v1/txt2img`

Current hardcoded payload:
```json
{
  "prompt": "...",
  "negative_prompt": "...",
  "width": 1024,
  "height": 1024,
  "steps": 20,
  "cfg_scale": 7,
  "sampler_name": "Euler a",
  "seed": -1,
  "batch_size": 1
}
```

Updated payload with user controls:
```json
{
  "prompt": "...",
  "negative_prompt": "...",
  "width": 1024,
  "height": 1024,
  "steps": 20,              // ← user configurable
  "cfg_scale": 7.0,         // ← user configurable
  "sampler_name": "Euler a",// ← user configurable
  "scheduler": "Automatic", // ← user configurable (advanced)
  "seed": -1,               // ← user configurable (advanced)
  "batch_size": 1           // ← user configurable (advanced)
}
```

### Fetching Server Capabilities
On "Test" connection success, fetch:
1. `GET /sdapi/v1/samplers` → `[{name, aliases, options}, ...]`
2. `GET /sdapi/v1/schedulers` → `[{name, label, aliases}, ...]`

Store in storage service so they persist across dialog opens.

---

## Storage Service Changes (`storage_service.dart`)

### New Fields
```dart
// Image generation - advanced
int    _imageGenSteps = 20;
double _imageGenCfgScale = 7.0;
String _imageGenSampler = 'Euler a';
int    _imageGenSeed = -1;
int    _imageGenBatchSize = 1;
String _imageGenScheduler = 'Automatic'; // advanced

// Cached server capabilities
List<String> _imageGenSamplers = [];
List<String> _imageGenSchedulers = [];
```

### New Getters/Setters
```dart
int get imageGenSteps => _imageGenSteps;
double get imageGenCfgScale => _imageGenCfgScale;
String get imageGenSampler => _imageGenSampler;
int get imageGenSeed => _imageGenSeed;
int get imageGenBatchSize => _imageGenBatchSize;
String get imageGenScheduler => _imageGenScheduler;
List<String> get imageGenSamplers => List.unmodifiable(_imageGenSamplers);
List<String> get imageGenSchedulers => List.unmodifiable(_imageGenSchedulers);

Future<void> setImageGenSteps(int value) async { ... }
Future<void> setImageGenCfgScale(double value) async { ... }
Future<void> setImageGenSampler(String value) async { ... }
Future<void> setImageGenSeed(int value) async { ... }
Future<void> setImageGenBatchSize(int value) async { ... }
Future<void> setImageGenScheduler(String value) async { ... }
Future<void> setImageGenSamplers(List<String> value) async { ... }
Future<void> setImageGenSchedulers(List<String> value) async { ... }
```

---

## Image Gen Service Changes (`image_gen_service.dart`)

### New Fetch Methods
```dart
/// Fetch available samplers from A1111/Draw Things server.
Future<List<String>> fetchA1111Samplers(String baseUrl) async {
  // GET /sdapi/v1/samplers
  // Returns sampler names
}

/// Fetch available schedulers from A1111/Draw Things server.
Future<List<String>> fetchA1111Schedulers(String baseUrl) async {
  // GET /sdapi/v1/schedulers
  // Returns scheduler names
}
```

### Update `_generateViaA1111()`
Change from hardcoded values to parameters:
```dart
Future<Uint8List> _generateViaA1111({
  // existing params...
  int steps = 20,
  double cfgScale = 7.0,
  String samplerName = 'Euler a',
  int seed = -1,
  int batchSize = 1,
  String scheduler = 'Automatic',
}) async {
  // Use params in payload
  final payload = <String, dynamic>{
    'prompt': effectivePrompt,
    'negative_prompt': negativePrompt,
    'width': width,
    'height': height,
    'steps': steps,
    'cfg_scale': cfgScale,
    'sampler_name': samplerName,
    'scheduler': scheduler,
    'seed': seed,
    'batch_size': batchSize,
  };
```

### Update `generateImage()`
Pass through storage values for local backends:
```dart
imageBytes = await _generateViaA1111(
  // existing params...
  steps:      _storage.imageGenSteps,
  cfgScale:   _storage.imageGenCfgScale,
  samplerName: _storage.imageGenSampler,
  seed:       _storage.imageGenSeed,
  batchSize:  _storage.imageGenBatchSize,
  scheduler:  _storage.imageGenScheduler,
);
```

---

## UI Changes (`image_gen_settings_dialog.dart`)

### Location
New section inserted **after** the existing Negative Prompt field, before the closing of `_buildSharedFields()`.

### Layout

```
┌─ Default Negative Prompt ──────────────────┐
│ [TextField: blurry, low quality...]        │
└────────────────────────────────────────────┘

┌─ Advanced Generation Settings ▼ ───────────┐
│                                            │
│  Sampling Steps:        [=====◉=====] 20   │
│                                            │
│  CFG Scale:             [=====◉=====] 7.0  │
│                                            │
│  Sampler:               [Euler a       ▼]  │
│                                            │
│  ┌─ Expert ────────────────────────────┐   │
│  │  Seed:         [    -1     ] [🎲]   │   │
│  │  Batch Size:   [◉───────] 1         │   │
│  │  Scheduler:    [Automatic     ▼]    │   │
│  └────────────────────────────────────┘   │
└────────────────────────────────────────────┘
```

### Widget Structure

```dart
Widget _buildAdvancedSettings(StorageService storage) {
  return ExpansionTile(
    title: const Text('Advanced Generation Settings',
        style: TextStyle(color: Colors.white54, fontSize: 13)),
    children: [
      // Steps slider
      _buildSliderField('Sampling Steps', 5, 50, storage.imageGenSteps,
          (v) => storage.setImageGenSteps(v)),
      
      // CFG Scale slider
      _buildSliderField('CFG Scale', 1.0, 20.0, storage.imageGenCfgScale,
          (v) => storage.setImageGenCfgScale(v), isDouble: true),
      
      // Sampler dropdown
      _buildSamplerDropdown(storage),
      
      // Expert section (nested expansion)
      ExpansionTile(
        title: const Text('Expert', style: TextStyle(fontSize: 11)),
        children: [
          _buildSeedField(storage),
          _buildSliderField('Batch Size', 1, 8, storage.imageGenBatchSize,
              (v) => storage.setImageGenBatchSize(v)),
          _buildSchedulerDropdown(storage),
        ],
      ),
    ],
  );
}
```

### Seed Field Behavior
- Default value: `-1` (random)
- Dice button: Sets to random int between 0-2147483647
- User can type any integer
- Empty field → treated as -1 (random)

### Sampler Dropdown
- Populated from `_storage.imageGenSamplers` when available
- Fallback hardcoded list: `['Euler a', 'Euler', 'DPM++ 2M Karras', 'DPM++ SDE Karras', 'DPM++ 2M SDE Karras', 'DDIM', 'UniPC']`
- Stored selection persists even if server doesn't list it

---

## Web UI Changes (`assets/web/js/app.js`)

Mirror the new fields in the web settings panel:
- Add slider inputs for steps and CFG
- Add dropdown for sampler
- Add seed input with randomize button
- Sync with `/api/settings` endpoint

---

## Implementation Order

1. **Storage service** — Add fields, getters/setters, load/save
2. **Image gen service** — Add fetch methods, update `_generateViaA1111()` and `generateImage()`
3. **Settings dialog** — Build advanced section UI
4. **Web UI** — Sync new fields
5. **Testing** — Verify with A1111, Forge, Draw Things backends

---

## Foot Gun Prevention

| Risk | Mitigation |
|------|------------|
| Invalid sampler name | Dropdown populated from server; fallback list; stored value validated against list |
| CFG too high (artifacts) | Slider capped at 20 (reasonable max); tooltip hints at 7-12 range |
| Steps too high (slow) | Slider capped at 50; tooltip notes diminishing returns after 30 |
| Batch size too high (OOM) | Slider capped at 8; tooltip warns about VRAM usage |
| Seed confusion | Default -1 clearly labeled "Random"; dice button for convenience |
| Scheduler incompatibility | Default "Automatic" delegates to sampler; only exposed in Expert section |

---

## Draw Things Specific Notes

Draw Things supports the same A1111 API parameters. The existing code already routes Draw Things through `_generateViaA1111()`, so no backend-specific changes needed. The only Draw Things-specific behavior is:
- `/sdapi/v1/unload-checkpoint` may not be supported (already handled gracefully)
- Model switching via `/sdapi/v1/options` works the same way

All new parameters (steps, cfg, sampler, seed, batch_size, scheduler) should work identically.
