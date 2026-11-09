# Generation Settings UI/UX Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform the Generation Settings page across Flutter desktop and React PWA into a high-density, categorized studio console featuring responsive dual-column samplers, constrained ranges with red danger highlights, and graphical default pips on slider tracks.

**Architecture:** Encapsulate slider track drawing in a custom `StudioSliderTrackShape` with danger-zone coloring and default-point pip rendering. Wrap each parameter into a modular `StudioSliderCard` in Flutter and an enhanced `SliderField` in React with CSS gradient tracks and absolute pip markers. Organize the screen into 4 distinct functional category cards, ensuring full desktop ↔ web parity and strict adherence to CI ratchets.

**Tech Stack:** Flutter / Dart (Desktop), React / TypeScript / CSS (Web PWA), Drift, Provider.

**Spec:** [docs/superpowers/specs/2026-11-09-generation-settings-ux-redesign-design.md](file:///d:/AI_Projects/Front%20Porch/docs/superpowers/specs/2026-11-09-generation-settings-ux-redesign-design.md)

## Global Constraints

- Size Law: Handwritten `lib/` Dart files must stay under 500 lines (`test/hygiene/god_file_ratchet_test.dart`).
- Theme Integrity: Zero raw `Colors.*` under `lib/`; use `AppColors.*Of(context)` and `StatusColors` exclusively (`test/hygiene/raw_colors_ratchet_test.dart`).
- Parity & Manifest: Web and desktop must maintain exact parity. Desktop markers `"Generation Parameters"` and `"Model transport"` in `generation_tab.dart` must remain intact (`test/hygiene/settings_parity_manifest_test.dart`).
- Existing Test Contracts: Existing label assertions in `test/ui/settings/sampler_knobs_test.dart` (e.g. `find.text('Temperature')`, `find.text('Min-P')`, etc.) and reset tooltips in `test/ui/settings/generation_value_reset_test.dart` must pass without modifications.
- Web Testing: `npm run lint` and `npm test` in `web_ui/` must pass cleanly.

## Review Focus

1. **Out-of-range custom/preset values:** If a loaded preset has a value outside the new constrained range (e.g., legacy Min-P = 0.5 where max is 0.25), the number input must display the honest value while the slider visually clamps to the max without crashing or throwing an assertion error.
2. **Danger zone visual boundaries:** When dragging within the safe range, active track displays normal form accent color; when dragged into the danger zone, the active track segment in the danger region paints with `AppColors.negativeAccentOf(context)`.
3. **Default pip positioning:** The graphical default pip must accurately align at normalized offset `(default - min) / (max - min)` on both desktop canvas and web range inputs across different screen widths (400px to 1440px).
4. **Responsive column collapse:** On screens $< 680$px wide, the dual-column sampler grid must gracefully collapse to a single column without overflow or clipping.
5. **Reset button coexistence:** The ↺ reset button must remain functional alongside the default pip, correctly targeting the chat model's recommended value or the app default.

---

### Task 1: Desktop Studio Slider Track Shape (`StudioSliderTrackShape`)

**Files:**
- Create: `lib/ui/settings/widgets/studio_slider_track_shape.dart`
- Test: `test/ui/settings/studio_slider_track_shape_test.dart`

**Interfaces:**
- Produces: `class StudioSliderTrackShape extends RoundedRectSliderTrackShape`
  - Constructor: `StudioSliderTrackShape({required double min, required double max, required double defaultVal, double? dangerMin, double? dangerMax, required BuildContext context})`
  - Overrides: `void paint(PaintingContext context, Offset offset, {required RenderBox parentBox, required SliderThemeData sliderTheme, required Animation<double> enableAnimation, required TextDirection textDirection, required Offset thumbCenter, Offset? secondaryOffset, bool isDiscrete, bool isEnabled, double additionalActiveTrackHeight})`

- [ ] **Step 1: Write the failing unit test**
Create `test/ui/settings/studio_slider_track_shape_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/settings/widgets/studio_slider_track_shape.dart';

void main() {
  testWidgets('StudioSliderTrackShape computes correct pip and danger metrics', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ),
    ));

    final shape = StudioSliderTrackShape(
      min: 0.0,
      max: 1.0,
      defaultVal: 0.7,
      dangerMax: 0.85,
      context: ctx,
    );

    expect(shape.defaultVal, 0.7);
    expect(shape.dangerMax, 0.85);
    expect(shape.normalizedDefault, closeTo(0.7, 1e-6));
    expect(shape.normalizedDangerMax, closeTo(0.85, 1e-6));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**
Run: `flutter test test/ui/settings/studio_slider_track_shape_test.dart`
Expected: FAIL with compilation error (class not found).

- [ ] **Step 3: Implement `StudioSliderTrackShape` in `lib/ui/settings/widgets/studio_slider_track_shape.dart`**
Implement the custom track shape:
- Compute normalized default: `(defaultVal - min) / (max - min)`.
- Compute normalized danger zones: `dangerMin != null ? (dangerMin - min) / (max - min) : null`, `dangerMax != null ? (dangerMax - min) / (max - min) : null`.
- In `paint()`:
  - Paint inactive track base in `AppColors.hairlineOf(context, 0.15)`.
  - Paint inactive danger segments in `AppColors.negativeAccentOf(context).withValues(alpha: 0.30)`.
  - Paint active track segment up to `thumbCenter.dx`.
  - If thumb extends into danger zone, paint the portion within the danger zone with `AppColors.negativeAccentOf(context)`.
  - Paint default pip: 2px wide, 8px high rounded vertical rect at `trackLeft + normalizedDefault * trackWidth` with `AppColors.textSecondary(context).withValues(alpha: 0.6)`.

- [ ] **Step 4: Run test to verify it passes**
Run: `flutter test test/ui/settings/studio_slider_track_shape_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add lib/ui/settings/widgets/studio_slider_track_shape.dart test/ui/settings/studio_slider_track_shape_test.dart
git commit -m "feat(ui): add StudioSliderTrackShape with danger zones and default pip"
```

---

### Task 2: Desktop Studio Slider Card Widget (`StudioSliderCard`)

**Files:**
- Create: `lib/ui/settings/widgets/studio_slider_card.dart`
- Test: `test/ui/settings/studio_slider_card_test.dart`

**Interfaces:**
- Consumes: `StudioSliderTrackShape` from Task 1, `ResetTarget`, `ValueResetButton` from `lib/ui/widgets/gen_presets/gen_presets.dart`.
- Produces: `class StudioSliderCard extends StatelessWidget`
  - Constructor parameters:
    - `required String label`
    - `required double value`
    - `required double min`
    - `required double max`
    - `required double defaultVal`
    - `double? dangerMin`
    - `double? dangerMax`
    - `required ValueChanged<double> onChanged`
    - `int? divisions`
    - `bool isInteger`
    - `int decimalPlaces`
    - `ResetTarget? reset`
    - `String? tooltip`

- [ ] **Step 1: Write the failing widget test**
Create `test/ui/settings/studio_slider_card_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/settings/widgets/studio_slider_card.dart';

void main() {
  testWidgets('StudioSliderCard renders label, input box, and responds to changes', (tester) async {
    double current = 0.7;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => StudioSliderCard(
            label: 'Temperature',
            value: current,
            min: 0.0,
            max: 1.6,
            defaultVal: 0.7,
            dangerMax: 1.25,
            onChanged: (val) => setState(() => current = val),
          ),
        ),
      ),
    ));

    expect(find.text('Temperature'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('0.70'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**
Run: `flutter test test/ui/settings/studio_slider_card_test.dart`
Expected: FAIL with compilation error (class not found).

- [ ] **Step 3: Implement `StudioSliderCard` in `lib/ui/settings/widgets/studio_slider_card.dart`**
- Structure:
  - Top row:
    - Parameter `label` (Text with `FontWeight.w600`, `fontSize: 13`).
    - Tooltip info icon if tooltip != null.
    - Spacer.
    - Reset button if value differs from reset target.
    - Compact text field (80px width) with tabular numerals (`FontFeatures: [FontFeature.tabularFigures()]`, `FontWeight.bold`, `fontSize: 13`).
  - Bottom row:
    - `SliderTheme` wrapping `Slider` with `trackShape: StudioSliderTrackShape(...)`.
    - Clamped slider value: `value.clamp(min, max)` so legacy out-of-range values don't throw Flutter slider assertion errors while displaying the actual numeric value in the box.
- Export in `lib/ui/settings/widgets/widgets.dart`.

- [ ] **Step 4: Run test to verify it passes**
Run: `flutter test test/ui/settings/studio_slider_card_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add lib/ui/settings/widgets/studio_slider_card.dart test/ui/settings/studio_slider_card_test.dart lib/ui/settings/widgets/widgets.dart
git commit -m "feat(ui): add StudioSliderCard widget with tabular input and pip slider"
```

---

### Task 3: Desktop Dual-Column Studio Sampler Rack (`GenerationSamplerSliders`)

**Files:**
- Modify: `lib/ui/settings/widgets/generation_sampler_sliders.dart`
- Test: `test/ui/settings/sampler_knobs_test.dart`, `test/ui/settings/generation_value_reset_test.dart`

**Interfaces:**
- Consumes: `StudioSliderCard` from Task 2, `samplerKnobsFor`, `StorageService`.
- Produces: Updated `GenerationSamplerSliders` rendering responsive 2-column layout with constrained ranges, danger zones, and default pips.

- [ ] **Step 1: Review existing tests for sampler sliders**
Run: `flutter test test/ui/settings/sampler_knobs_test.dart`
Expected: PASS currently.
Run: `flutter test test/ui/settings/generation_value_reset_test.dart`
Expected: PASS currently.

- [ ] **Step 2: Update `GenerationSamplerSliders` with dual-column layout and new constrained ranges**
In `lib/ui/settings/widgets/generation_sampler_sliders.dart`:
- Use `LayoutBuilder` to toggle between 2 columns ($\ge 680$px) and 1 column ($< 680$px).
- Column 1 (Creativity & Probability):
  - **Temperature**: min `0.0`, max `1.60`, default `0.70`, dangerMax `1.25`.
  - **Min-P**: min `0.0`, max `0.25`, default `0.10`, dangerMax `0.15`.
  - **Top-P**: min `0.50`, max `1.00`, default `0.90`, dangerMin `0.65`.
  - **Top-K**: min `0`, max `100`, default `0`, dangerMax `75`, isInteger `true`.
  - **Dynamic Temperature**: Switch row + **Dynatemp Range** slider (min `0.0`, max `1.00`, default `0.50`, dangerMax `0.70`).
- Column 2 (Flow & Anti-Repetition):
  - **DRY Strength**: min `0.0`, max `1.60`, default `0.0`, dangerMax `1.20`.
  - **Repeat Penalty**: min `1.00`, max `1.35`, default `1.10`, dangerMax `1.20`.
  - **Repeat Penalty Tokens**: min `0`, max `2048`, default `1024`, dangerMin `128`, isInteger `true`, divisions `32`.
  - **XTC Threshold**: min `0.0`, max `0.30`, default `0.10`, dangerMax `0.20`.
  - **XTC Probability**: min `0.0`, max `1.00`, default `0.0`, dangerMax `0.60`.
- Keep all parameter labels exact so `find.text('Temperature')`, `find.text('Min-P')`, etc. match.
- Keep `reset: r((v) => ...)` so `ValueResetButton` tooltips match `generation_value_reset_test.dart`.

- [ ] **Step 3: Run existing tests to verify they pass**
Run: `flutter test test/ui/settings/sampler_knobs_test.dart`
Expected: PASS across all 5 backends.
Run: `flutter test test/ui/settings/generation_value_reset_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**
```bash
git add lib/ui/settings/widgets/generation_sampler_sliders.dart
git commit -m "feat(ui): convert GenerationSamplerSliders to responsive dual-column studio rack with danger zones"
```

---

### Task 4: Desktop Categorized Generation Tab (`GenerationTab` & `GenerationAdvancedSection`)

**Files:**
- Create: `lib/ui/settings/widgets/generation_advanced_section.dart`
- Modify: `lib/ui/settings/tabs/generation_tab.dart`
- Test: `test/hygiene/god_file_ratchet_test.dart`, `test/hygiene/settings_parity_manifest_test.dart`

**Interfaces:**
- Produces: `GenerationAdvancedSection` (Model transport toggle + Smooth Display Buffer settings).
- Updates: `GenerationTab` structured into 4 distinct semantic cards with polished typography and spacing.

- [ ] **Step 1: Create `lib/ui/settings/widgets/generation_advanced_section.dart`**
Extract "Model transport" and "Display Output" into an expandable / clean advanced card:
- Contains the exact marker string: `'Model transport'` (required by `settings-parity-manifest.json`).
- Handles native tool calling switch.
- Handles smooth output buffer switch, target display speed slider (5–60), and buffer duration slider (1–10).
- Keeps file $< 150$ lines.

- [ ] **Step 2: Refactor `lib/ui/settings/tabs/generation_tab.dart` into 4 categories**
In `generation_tab.dart`:
- Card 1: **Preset & Reasoning**
  - `GenerationPresetBar`
  - `SectionHeader('Thinking')` + `ThinkingSettingsBlock`
- Card 2: **Sampling & Creativity**
  - `SectionHeader('Generation Parameters')` (required by `settings-parity-manifest.json`)
  - Sub-captions for column domains
  - `GenerationSamplerSliders`
- Card 3: **Context & Token Budgets**
  - `SectionHeader('Output Limits')`
  - `Max Output Tokens` (constrained `64` to `8192`, default `2048`, dangerMin `128`)
  - `Context Size` + `ContextSizeWarnings`
- Card 4: **Output Pipeline & Diagnostics**
  - `SectionHeader('Stop Sequences')` + `StopSequenceList`
  - `Banned Phrases` (when active)
  - `SectionHeader('Output Sanitizer')` + rules editor
  - `GenerationAdvancedSection`
- Check line count: ensure `generation_tab.dart` is under 300 lines (well under 500-line ceiling).

- [ ] **Step 3: Verify CI hygiene ratchets and parity**
Run: `flutter test test/hygiene/god_file_ratchet_test.dart`
Expected: PASS (zero files $\ge 500$ lines).
Run: `flutter test test/hygiene/settings_parity_manifest_test.dart`
Expected: PASS (markers `'Generation Parameters'` and `'Model transport'` verified in `generation_tab.dart`).
Run: `flutter test test/hygiene/raw_colors_ratchet_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**
```bash
git add lib/ui/settings/widgets/generation_advanced_section.dart lib/ui/settings/tabs/generation_tab.dart lib/ui/settings/widgets/widgets.dart
git commit -m "refactor(ui): organize GenerationTab into 4 distinct functional cards"
```

---

### Task 5: Web UI Slider with Danger Zones and Default Pip

**Files:**
- Modify: `web_ui/src/components/GenerationSettingsFields.tsx`
- Modify: `web_ui/src/styles/settings.css`
- Test: `web_ui/src/components/GenerationSettingsFields.reset.test.tsx`, `web_ui/src/components/GenerationSettingsFields.samplerKnobs.test.tsx`

**Interfaces:**
- Enhances: `SliderField` in `GenerationSettingsFields.tsx` with:
  - `defaultVal?: number`
  - `dangerMin?: number`
  - `dangerMax?: number`
- Produces: CSS track danger styling and `.slider-default-pip` marker.

- [ ] **Step 1: Update `SliderField` in `web_ui/src/components/GenerationSettingsFields.tsx`**
Add props to `SliderField`:
```tsx
defaultVal?: number;
dangerMin?: number;
dangerMax?: number;
```
Calculate normalized percentages:
- `defaultPct = defaultVal !== undefined ? ((defaultVal - min) / (max - min)) * 100 : null`
- Danger zone gradient background for the native range slider track:
  ```css
  background: dangerMax !== undefined 
    ? `linear-gradient(to right, var(--color-hairline) 0%, var(--color-hairline) ${dangerMaxPct}%, rgba(239, 68, 68, 0.35) ${dangerMaxPct}%, rgba(239, 68, 68, 0.35) 100%)`
    : ...
  ```
- Render pip:
  ```tsx
  {defaultPct !== null && (
    <span
      className="slider-default-pip"
      style={{ left: `${defaultPct}%` }}
      aria-hidden="true"
    />
  )}
  ```

- [ ] **Step 2: Add CSS in `web_ui/src/styles/settings.css`**
Add styling:
```css
.slider-track-wrap {
  position: relative;
  width: 100%;
  display: flex;
  align-items: center;
}

.slider-default-pip {
  position: absolute;
  top: 50%;
  transform: translate(-50%, -50%);
  width: 2px;
  height: 10px;
  background-color: var(--color-text-secondary);
  opacity: 0.6;
  border-radius: 1px;
  pointer-events: none;
  z-index: 1;
}

.studio-sampler-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
  gap: 16px;
  margin-top: 12px;
  margin-bottom: 16px;
}
```

- [ ] **Step 3: Run web tests to verify no regressions in reset or knobs**
Run: `cd web_ui && npm test`
Expected: PASS.

- [ ] **Step 4: Commit**
```bash
git add web_ui/src/components/GenerationSettingsFields.tsx web_ui/src/styles/settings.css
git commit -m "feat(web_ui): add danger zone gradients and default pip to SliderField"
```

---

### Task 6: Web UI Categorized Generation Card Layout & Constrained Ranges

**Files:**
- Modify: `web_ui/src/components/GenerationSettingsFields.tsx`
- Test: `web_ui/src/components/GenerationSettingsFields.contextFloor.test.tsx`, `web_ui/src/components/GenerationSettingsFields.contextLock.test.tsx`, `web_ui/src/pages/SettingsPage.parity.test.tsx`

**Interfaces:**
- Updates: `GenerationSettingsFields` component to categorize controls into the 4 semantic cards and apply the matching constrained ranges, danger zones, and default pips to all samplers.

- [ ] **Step 1: Update sampler slider ranges and cards in `GenerationSettingsFields.tsx`**
Align all sampler slider ranges and danger boundaries with Desktop Task 3:
- Temperature: min `0`, max `1.6`, default `0.70`, dangerMax `1.25`, step `0.05`.
- Min-P: min `0`, max `0.25`, default `0.10`, dangerMax `0.15`, step `0.01`.
- Top-P: min `0.50`, max `1.0`, default `0.90`, dangerMin `0.65`, step `0.01`.
- Top-K: min `0`, max `100`, default `0`, dangerMax `75`, step `1`.
- Repeat penalty: min `1.0`, max `1.35`, default `1.10`, dangerMax `1.20`, step `0.01`.
- Rep pen tokens: min `0`, max `2048`, default `1024`, dangerMin `128`, step `64`.
- DRY strength: min `0`, max `1.6`, default `0`, dangerMax `1.20`, step `0.05`.
- XTC threshold: min `0`, max `0.30`, default `0.10`, dangerMax `0.20`, step `0.01`.
- XTC probability: min `0`, max `1.0`, default `0`, dangerMax `0.60`, step `0.05`.
- Dynatemp range: min `0`, max `1.0`, default `0.50`, dangerMax `0.70`, step `0.05`.
- Max output tokens: min `64`, max `8192`, default `2048`, dangerMin `128`, step `32`.
- Wrap samplers into `.studio-sampler-grid`.

- [ ] **Step 2: Run web tests and linter**
Run: `cd web_ui && npm run lint && npm test`
Expected: PASS with 0 lint errors and all tests passing.
Run: `cd web_ui && npm run build`
Expected: Build succeeds and updates `assets/web_app`.

- [ ] **Step 3: Commit**
```bash
git add web_ui/src/components/GenerationSettingsFields.tsx web_ui/src/styles/settings.css assets/web_app
git commit -m "feat(web_ui): update GenerationSettingsFields to categorized studio grid with constrained ranges"
```

---

### Task 7: Full Hygiene & System Verification

**Files:**
- Test all touched surfaces.

- [ ] **Step 1: Run Dart analyzer**
Run: `flutter analyze lib/ui/settings/`
Expected: Zero issues found.

- [ ] **Step 2: Run Flutter hygiene tests**
Run: `flutter test test/hygiene/god_file_ratchet_test.dart`
Expected: PASS.
Run: `flutter test test/hygiene/raw_colors_ratchet_test.dart`
Expected: PASS.
Run: `flutter test test/hygiene/settings_parity_manifest_test.dart`
Expected: PASS.

- [ ] **Step 3: Run Flutter UI & Settings test suites**
Run: `flutter test test/ui/settings/sampler_knobs_test.dart`
Expected: PASS.
Run: `flutter test test/ui/settings/generation_value_reset_test.dart`
Expected: PASS.
Run: `flutter test test/ui/settings/studio_slider_track_shape_test.dart`
Expected: PASS.
Run: `flutter test test/ui/settings/studio_slider_card_test.dart`
Expected: PASS.

- [ ] **Step 4: Run Web UI test and build suite**
Run: `cd web_ui && npm test && npm run lint`
Expected: PASS.

- [ ] **Step 5: Final integration commit**
```bash
git commit --allow-empty -m "chore: verify generation settings redesign meets all parity and CI ratchets"
```
