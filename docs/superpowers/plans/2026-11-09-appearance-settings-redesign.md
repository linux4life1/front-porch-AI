# Appearance Settings UI/UX Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign Appearance Settings across Flutter desktop and React web_ui with a 4-tier functional information architecture, high-contrast typography hierarchy, a space-saving WYSIWYG live chat capsule, and paired split-pill color tokens.

**Architecture:**
- **Desktop (Flutter):** Restructure `lib/ui/settings/tabs/appearance_tab/` into 4 cohesive visual domains. Extract an interactive `ChatCapsulePreview` and `ChatColorMatrix` to replace 6 standalone `ColorRow` widgets with paired background/text pills. Upgrade `AccentPickerRow` into a streamlined accent bar with contrast awareness. Unify reading scale and chat font under "Chat Typography & Readability", and group Background Weather and Realism Mood under "Atmosphere & Immersion".
- **Web (`web_ui`):** Update `AppearanceSettings.tsx` and `ChatColorsSettings.tsx` with matching 4-category cards, semantic split-pill color controls, and refined typography in `settings.css`.
- **Hygiene & Parity:** Preserve all `dartMarker` and `webMarker` pins in `docs/design/settings-parity-manifest.json`, maintain strict <500 lines per file, zero raw colors, and ensure full light/dark theme compliance.

**Tech Stack:** Flutter desktop (Dart), React 18 / TypeScript, Vite, CSS custom properties (`var(--...)`).

---

## Global Constraints

- **Size Law:** Handwritten `lib/` Dart files must stay strictly under 500 lines (`god_file_ratchet_test`).
- **Style:** Zero raw `Colors.*` in UI (`raw_colors_ratchet_test`). Chrome and accents must read `AppColors.*Of(context)` and `palette.*`.
- **Parity:** Desktop and `web_ui` changes must ship in step. `settings_parity_manifest_test` pins markers in Dart and TSX files.
- **Responsiveness:** UI must scale gracefully between 400px (narrow window/sidebar) and 1440px (wide desktop).
- **Test Integrity:** All existing tests in `test/services/`, `test/ui/settings/`, `test/hygiene/`, and `web_ui` must pass.

---

## Review Focus

1. **Parity Marker Preservation:** Verify `Reading Size`, `Ambient scene`, `Pause effects while generating`, `Scene sound`, `Scene sound volume`, `Mood on the character`, `Drama`, and `Chat Appearance` remain intact in their designated Dart files.
2. **Narrow Viewport (400px):** Verify chat bubble preview and split-pill matrix stack cleanly without horizontal overflow.
3. **Contrast Rating & WCAG:** Ensure text rendered inside swatch chips and preview bubbles meets minimum 4.5:1 ratio or indicates adjusted status.
4. **Theme Reactivity:** Confirm dynamic switching across all 8 themes (Porch, Slate, Graphite, Midnight, Evergreen, Plum, Harbor, High Contrast) in both Dark and Light modes updates all preview components immediately.
5. **Color Literals Lint:** Verify `web_ui/src/theme/colorLiterals.test.ts` passes without false positives.

---

## File Map

| Path | Action | Responsibility |
| :--- | :--- | :--- |
| `lib/ui/settings/tabs/appearance_tab/chat_capsule_preview.dart` | Create | Live interactive micro-chat bubble preview (User + AI turn with dialogue and actions) |
| `lib/ui/settings/tabs/appearance_tab/chat_color_matrix.dart` | Create | Paired split-pill color tokens: User [Bubble \| Ink], AI [Bubble \| Ink \| Quote \| Action] |
| `lib/ui/settings/tabs/appearance_tab/chat_typography_section.dart` | Create | Unified Reading Scale slider (with live % badge) + Chat Font dropdown |
| `lib/ui/settings/tabs/appearance_tab/chat_appearance_section.dart` | Modify | Orchestrate Chat Typography + Chat Color Matrix + WYSIWYG Capsule + Reset button |
| `lib/ui/settings/tabs/appearance_tab/accent_picker_row.dart` | Modify | Streamlined accent selector: Theme default pill, curated hue track, custom picker + contrast tag |
| `lib/ui/settings/tabs/appearance_tab/appearance_tab.dart` | Modify | 4-category layout with refined typography and visual section separators |
| `web_ui/src/components/ChatColorsSettings.tsx` | Modify | Web twin: Paired split-token inputs, live chat sample, and contrast-aware chips |
| `web_ui/src/components/AppearanceSettings.tsx` | Modify | Card categorization and typography alignment with desktop structure |
| `web_ui/src/styles/settings.css` | Modify | CSS styles for capsule preview, split-pill tokens, and typography hierarchy |
| `web_ui/src/components/PromptSettingsCard.tsx` | Modify | Fix `&#123;` false-positive triggering `colorLiterals.test.ts` |
| `web_ui/src/components/PromptSlot.tsx` | Modify | Fix `&#123;` false-positive triggering `colorLiterals.test.ts` |
| `test/ui/settings/appearance_chat_capsule_test.dart` | Create | Unit/widget test for live capsule preview and color token binding |

---

## Implementation Tasks

### Task 1: Clean Up Macro Entity False Positives in Web UI
- [ ] In `web_ui/src/components/PromptSettingsCard.tsx`, replace `&#123;&#123;char&#125;&#125;` with `{ '{{char}}' }` or plain `{{char}}` to avoid regex match `#123` in `colorLiterals.test.ts`.
- [ ] In `web_ui/src/components/PromptSlot.tsx`, replace `&#123;&#123;char&#125;&#125;` with `{ '{{char}}' }` or plain `{{char}}`.
- [ ] Run `npx vitest run src/theme/colorLiterals.test.ts` with Node 22 to confirm zero color literal violations.

### Task 2: Build the Flutter Desktop Chat Capsule Preview
- [ ] Create `lib/ui/settings/tabs/appearance_tab/chat_capsule_preview.dart`.
- [ ] Render a compact (height ~100-110px) 2-bubble conversation inside a subtle container:
  - User bubble on right with `globalUserBubbleColor` and `globalUserTextColor`.
  - AI bubble on left with `globalAiBubbleColor`, `globalAiTextColor`, `globalDialogueColor`, and `globalActionColor`.
- [ ] Apply current `UiSettings.textScale` and `UiSettings.globalChatFontFamily`.
- [ ] Ensure all colors fallback to the current `AppPalette` when uncustomized.
- [ ] Respect `AppCorners.of(context)` for bubble corners.

### Task 3: Build the Paired Split-Pill Color Matrix
- [ ] Create `lib/ui/settings/tabs/appearance_tab/chat_color_matrix.dart`.
- [ ] Implement paired split-pill tokens:
  - **User Message**: Fill Swatch + Text Ink ("Aa" sample on fill color).
  - **Character Message**: Fill Swatch + Text Ink ("Aa" sample on fill color).
  - **Character Dialogue & Actions**: Compact chip pair showing `"Quote"` and `*Action*` text in their colors.
- [ ] Connect tapping each chip to `showColorPicker`.
- [ ] Add real-time WCAG contrast badges (e.g. `✓ 4.5:1 AA`).

### Task 4: Unify Chat Typography & Scale
- [ ] Create `lib/ui/settings/tabs/appearance_tab/chat_typography_section.dart`.
- [ ] Move `Reading Size` slider here with an inline value badge (e.g. `1.0x`, `1.2x (+20%)`).
- [ ] Move `Chat Font` dropdown here, adding styled typography samples.
- [ ] Keep marker string `Reading Size` intact.

### Task 5: Refactor ChatAppearanceSection & AccentPickerRow
- [ ] In `accent_picker_row.dart`, redesign layout:
  - Hero chip for "Theme Accent".
  - Compact row of curated swatches.
  - Custom color button with real-time contrast feedback.
- [ ] In `chat_appearance_section.dart`:
  - Integrate `ChatTypographySection`, `ChatCapsulePreview`, and `ChatColorMatrix`.
  - Maintain marker strings `Reading Size` and `Chat Appearance` so `settings_parity_manifest_test.dart` passes.
  - Keep file under 500 lines.

### Task 6: Refactor AppearanceTab Master Layout
- [ ] In `lib/ui/settings/tabs/appearance_tab/appearance_tab.dart`:
  - Organize into 4 clearly demarcated sections with consistent typography:
    1. **App Shell & Theme** (`SectionHeader('App Shell & Theme')` or `'Theme'`)
    2. **Chat Typography & Readability**
    3. **Chat Message Palette**
    4. **Atmosphere & Immersion** (housing `BackgroundWeatherSection` and `MoodOnCharacterControls`)
  - Ensure all existing ValueKeys (`appearance-mode`, `appearance-font`, `appearance-corners`, `appearance-reset`, etc.) remain identical.

### Task 7: Update Web UI Appearance & Chat Colors Components
- [ ] Update `web_ui/src/components/ChatColorsSettings.tsx`:
  - Reorganize 6 inputs into paired User / Character cards with nested text samples.
  - Refine preview capsule styling.
- [ ] Update `web_ui/src/styles/settings.css`:
  - Add styles for capsule preview, split-token buttons, and contrast indicators.
- [ ] Verify `npm run lint` and `npm test` in `web_ui`.

### Task 8: Verification & Hygiene Checks
- [ ] Run `npm run lint` and `npm test` in `web_ui`.
- [ ] Verify parity manifest markers via `test/hygiene/settings_parity_manifest_test.dart`.
- [ ] Verify all touched Dart files are under 500 lines and use zero raw colors.
