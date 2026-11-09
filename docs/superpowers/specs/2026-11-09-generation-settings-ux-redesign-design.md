# Generation Settings UI/UX Redesign

**Date:** 2026-11-09  
**Status:** Draft design doc for user review  
**Audience:** Implementing agents and maintainers  
**Surfaces:** Flutter desktop (`lib/ui/settings/tabs/generation_tab.dart`, widgets) and `web_ui` (`web_ui/src/components/GenerationSettingsFields.tsx`, styles) in the **same implementation PR** (parity law).  

---

## 1. Intent & The Why

The Generation Settings screen controls how LLMs write responses (sampling temperature, nucleus pruning, repetition suppression, context memory, and output formatting). 

Currently, the screen suffers from:
1. **Monolithic Layout:** 9 flat sections stacked vertically in an undifferentiated 1500px+ scroll. Runtime sampling math is mixed together with token capacity constraints, diagnostic transport toggles, and UI typewriter display animations.
2. **Spatial Waste:** Each slider stretches across the entire window (up to 1200px wide on desktop), forcing users to scroll through 700+ pixels of vertical height just to see basic samplers.
3. **Usability Traps:** Sliders have unconstrained ranges with massive "dead/destructive zones" (e.g., Min-P up to 1.0 where >0.20 causes vocabulary collapse; Repeat Penalty up to 3.0 where >1.30 breaks English grammar).
4. **Missing Default Anchors:** Sliders provide no visual cue showing where the neutral or baseline setting sits on the track.

This redesign reorganizes the settings into clear functional categories, introduces a dual-column studio console for samplers, constrains slider ranges to meaningful values with 20% danger boundaries highlighted in red, and renders a clean graphical default indicator pip directly on the track.

---

## 2. Goals, Non-Goals & Anti-Goals

### Goals
- **Dual-Column Studio Rack (Approach 1):** Present sampler sliders in a responsive 2-column layout on desktop (collapsing to 1 column on narrow screens/phones), pairing complementary parameters (Creativity on the left, Anti-Repetition on the right).
- **Clear Information Categorization:** Partition the page into 4 semantic cards:
  1. *Preset & Reasoning* (Model intelligence & preset bar)
  2. *Sampling & Creativity* (Dual-column sampler rack)
  3. *Context & Token Budgets* (Memory & output limits)
  4. *Output Pipeline & Diagnostics* (Stop sequences, sanitizer, advanced engine transport & streaming display)
- **Constrained Ranges with Red Danger Zones:** Constrain slider ranges to values that make practical sense for LLMs, expanded by 20% on danger boundaries. Paint danger segments with red alert coloring (`AppColors.negativeAccentOf(context)` / `--status-error`).
- **Graphical Default Pip:** Render a subtle, clean tick/pip mark on the slider track at the default/baseline point without cluttering text.
- **Tabular Figures & Typography Hierarchy:** Ensure parameter numbers use tabular numerals (`FontFeature.tabularFigures()`) to prevent layout jitter while dragging. Use distinct type scale and weights for categories, labels, and helper cues.
- **Desktop ↔ Web Parity:** Maintain exact parity in `web_ui/src/components/GenerationSettingsFields.tsx`.

### Non-Goals
- Changing backend wire payload schemas or model communication protocols.
- Altering the underlying `SamplerValues` or `GenerationSettings` persistence models.
- Removing or hiding any existing supported samplers or settings.

### Anti-Goals (What would make this a failure)
- Breaking test assertions that search for parameter labels (e.g., `find.text('Temperature')`, `find.text('Min-P')`).
- Violating the 500-line size ratchet in any `lib/` Dart file.
- Introducing raw colors outside `AppColors` / `StatusColors`.
- Desynchronizing desktop and web settings (`settings_parity_manifest_test`).

---

## 3. Approaches Considered & Selection

| Approach | Description | Tradeoffs | Verdict |
| :--- | :--- | :--- | :--- |
| **Approach 1: Dual-Column Studio Console** | Pairs complementary samplers into a 2-column studio rack with embedded default pips and danger zones. | Requires responsive column handling, but cuts vertical height by ~50% and groups related concepts. | **SELECTED by user.** |
| **Approach 2: Progressive Disclosure** | Exposes only Temperature, Min-P, and Max Output, hiding the rest behind "Advanced". | Hides power controls behind extra clicks; frustrating for advanced users. | Dropped. |
| **Approach 3: Unified Single-Line Strips** | Ultra-dense 36px horizontal rows with inline track. | Can feel cramped on tablet/mobile screens and reduces drag precision. | Dropped. |

---

## 4. Parameter Ranges, Danger Zones & Default Points

Each slider defines:
- **Default Value ($D$):** Graphical pip rendered on the track.
- **Safe Working Range:** Standard operational territory.
- **Danger Zone(s):** 20% expanded boundary where values risk output degradation, highlighted with red track styling.

| Parameter | Slider Range $[Min, Max]$ | Default Pip | Danger Zone | Reason for Danger Highlight |
| :--- | :---: | :---: | :---: | :--- |
| **Temperature** | `0.0 – 1.60` (step 0.05) | **0.70** | `> 1.25` (red track) | Extreme hallucination, syntax breakdown, chaotic randomness |
| **Min-P** | `0.0 – 0.25` (step 0.01) | **0.10** | `> 0.15` (red track) | Severe vocabulary starvation; repetition of single tokens |
| **Top-P (Nucleus)** | `0.50 – 1.00` (step 0.01) | **0.90** | `< 0.65` (red track) | Over-pruning cumulative distribution; truncated responses |
| **Top-K** | `0 – 100` (step 1) | **0** (Off) | `> 75` (red track) | Diminishing returns and negligible probability tail |
| **Repeat Penalty** | `1.00 – 1.35` (step 0.01) | **1.10** | `> 1.20` (red track) | Grammar fracturing, extreme synonym substitution, broken speech |
| **Rep Pen Tokens** | `0 – 2048` (step 64) | **1024** | `< 128` (red track) | Context window too small to prevent loop spirals |
| **DRY Strength** | `0.0 – 1.60` (step 0.05) | **0.0** (Off) | `> 1.20` (red track) | Heavy over-penalization of natural idioms and repeated dialogue |
| **XTC Threshold** | `0.0 – 0.30` (step 0.01) | **0.10** | `> 0.20` (red track) | Disproportionate exclusion of natural high-probability tokens |
| **XTC Probability** | `0.0 – 1.00` (step 0.05) | **0.0** (Off) | `> 0.60` (red track) | Excessive randomness forcing unnatural phrasing |
| **Dynatemp Range** | `0.0 – 1.00` (step 0.05) | **0.50** | `> 0.70` (red track) | Temperature swings too wide around base value |
| **Max Output Tokens**| `64 – 8192` (step 32) | **2048** | `< 128` (red track) | Truncation of thinking tokens or complete sentences |

*Note on existing presets/custom values:* If a user or external preset loads a value outside the constrained range (e.g. legacy Min-P = 0.5), the slider clamps visually or displays an out-of-range badge while preserving precision in the number box.

---

## 5. Information Architecture & Layout Structure

### Card 1: Preset & Reasoning (`Model Intelligence`)
- **Generation Preset Bar:** Saved preset selector, [Save], [Save as new], [Reset all to defaults], and follower recommendation banner.
- **Thinking Block:** Request Thinking toggle + Thinking Strength chips (Low / Medium / High / Max) with model support caption.

### Card 2: Sampling & Creativity (`Text Generation Studio`)
Header: **Generation Parameters** (satisfies `settings-parity-manifest.json`).  
Sub-header / Eyebrows:
- **Left Column: Creativity & Probability**
  - Temperature (with Dynamic Temperature expander/toggle underneath)
  - Min-P
  - Top-P
  - Top-K (when active for backend)
- **Right Column: Flow & Anti-Repetition**
  - DRY Strength (KoboldCpp/oMLX)
  - Repeat Penalty
  - Repeat Penalty Tokens
  - XTC Threshold & Probability (KoboldCpp/oMLX)

### Card 3: Context & Token Budgets (`Memory & Capacity`)
- **Context Size:** Slider with `.kcpps` preset lock badge, context floor warning (`< 16384`), and context fill warning.
- **Max Output Tokens:** Slider with reset button and context reserve calculation.

### Card 4: Output Pipeline & Diagnostics (`Filters, Rules & Engine`)
- **Stop Sequences:** Chip/tag editor with Add/Remove.
- **Banned Phrases:** KoboldCpp-only banned phrase multi-line editor.
- **Output Sanitizer:** Toggle, "Sanitise Existing History" destructive switch with warm dialog confirmation, and Rule Editor.
- **Advanced Engine Options (Collapsible / Accordion):**
  - *Model Transport:* Native tool calling toggle for Realism/Journal evaluations.
  - *Display Output:* Smooth output buffer toggle, Target display speed (t/s), and Buffer duration sliders.

---

## 6. UI Component Design & Implementation Details

### Desktop (Flutter)

1. **`StudioSliderTrackShape`** (extends `RoundedRectSliderTrackShape`):
   - Paints the slider track in 3 regions:
     - `inactiveTrackColor`: Base track color (`AppColors.hairlineOf(context, 0.15)`).
     - `dangerZone`: Segments beyond the danger threshold painted in `AppColors.negativeAccentOf(context).withValues(alpha: 0.35)` (or solid on active segment).
     - `activeTrack`: Painted with `AppColors.formAccentOf(context)`. If thumb is inside a danger zone, the active track smoothly transitions to `AppColors.negativeAccentOf(context)`.
   - Paints the **Default Pip**:
     - At offset `x = trackLeft + (default - min) / (max - min) * trackWidth`.
     - Draws a 2px-wide, 8px-high rounded vertical pip in high-contrast neutral (`AppColors.textSecondary(context)`).

2. **`StudioSliderCard`** (Widget):
   - Encapsulates:
     - Top row: `label` (Text) + `[↺]` (ValueResetButton if differs from recommended/default) + `NumberInputBox` (80px wide with tabular numerals).
     - Bottom row: Slider with `StudioSliderTrackShape` and default pip.
   - Fits comfortably in a 2-column `LayoutBuilder` grid (width $\ge 680$px: 2 columns; width $< 680$px: 1 column).

3. **File Size Law Compliance**:
   - `generation_tab.dart` delegates to modular widget files:
     - `lib/ui/settings/widgets/generation_sampler_sliders.dart` (Dual-column studio grid).
     - `lib/ui/settings/widgets/studio_slider_card.dart` (The compact card widget, $< 200$ lines).
     - `lib/ui/settings/widgets/studio_slider_track_shape.dart` (The custom slider track painter, $< 150$ lines).
     - `lib/ui/settings/widgets/generation_advanced_section.dart` (Model transport + display output, $< 150$ lines).
   - Keeps all touched files well under the 500-line ceiling.

### Web (`web_ui`)

1. **`SliderField` Redesign (`GenerationSettingsFields.tsx`)**:
   - Accepts `defaultVal?: number`, `dangerMin?: number`, `dangerMax?: number`.
   - Computes CSS background gradient for the native range input:
     - Danger zones colored with `rgba(239, 68, 68, 0.3)` (red).
     - Standard track colored with `var(--color-bg-secondary)`.
   - Embeds a `<span className="slider-default-pip" style={{ left: `${defaultPct}%` }} />` directly on the track container.
2. **CSS Styles (`web_ui/src/styles/settings.css`)**:
   - Adds `.studio-slider-grid` (CSS Grid: `grid-template-columns: repeat(auto-fit, minmax(280px, 1fr))`).
   - Adds `.studio-slider-card` styling for high-density, clean visual hierarchy.

---

## 7. Test Strategy & Verification Plan

1. **Hygiene & Parity Ratchets:**
   - `test/hygiene/god_file_ratchet_test.dart` (all `lib/` Dart files under 500 lines).
   - `test/hygiene/raw_colors_ratchet_test.dart` (no raw `Colors.*`).
   - `test/hygiene/settings_parity_manifest_test.dart` (markers `"Generation Parameters"` and `"Model transport"` exist in `generation_tab.dart`).
2. **Unit & Widget Tests:**
   - `test/ui/settings/sampler_knobs_test.dart` (asserts all parameter labels are findable per backend).
   - `test/ui/settings/generation_value_reset_test.dart` (asserts ↺ reset buttons still function and tooltips match).
   - New unit tests for `StudioSliderTrackShape` and danger-zone calculation.
3. **Web Tests:**
   - `npm run lint` and `npm test` in `web_ui/`.
   - `web_ui/src/components/GenerationSettingsFields.*.test.tsx` (reset, context floor, sampler knobs).
4. **Hand-check & Poke Script:**
   - Verify visually under light and dark modes in Porch and non-Porch themes.
   - Verify drag interaction in safe zone vs red danger zone.
   - Verify default pip alignment at different window widths (400px to 1440px).
