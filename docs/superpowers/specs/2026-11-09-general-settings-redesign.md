# General Settings UI/UX Redesign

**Date:** 2026-11-09  
**Status:** In review / Design approved by user  
**Author:** Pair programming session (Antigravity & User)  
**Scope:** Flutter desktop (`lib/ui/settings/tabs/general_tab.dart`); Web companion redesign deferred by maintainer (parity maintained via manifest)  
**Parity Manifest:** `docs/design/settings-parity-manifest.json`  

---

## 1. Intent & The Why

General Settings is currently an uncurated "catch-all" screen resulting from organic feature growth. The top of the page features floating orphan switches with no category header (`userMessagesOnRight`, `followStreamingReplies`), followed by network update controls, spell check configuration, an awkwardly placed "Porch Life" section (containing only an 18+ toggle and an apology card), three massive prompt engineering blocks dominating 65% of the vertical space, and an About & License card at the bottom.

Furthermore, typography across controls is fragmented and inconsistent: font sizes are hardcoded at 11px, 12px, 12.5px, 13px, 14px, 16px, and 18px; helper texts and subtitles use conflicting opacity/color tokens; and `PromptSlotCard` reuses top-level amber `SectionHeader` components for internal slots, collapsing the visual hierarchy.

The goal of this redesign is to significantly improve usability by:
1. **Categorizing controls into 4 coherent, visually unified card groups**.
2. **Establishing a disciplined 2-level typographic hierarchy** that distinguishes Category Headers, Section Titles, Control Labels, Explanatory Copy, and Prompt Code/Tokens.
3. **Preserving 100% desktop/web parity and automated CI compliance** without breaking `settings_parity_manifest_test.dart` or violating the 500-line ratchet law ([CLAUDE.md](file:///d:/AI_Projects/Front%20Porch/CLAUDE.md)).

---

## 2. Goals, Non-Goals, and Anti-Goals

### Goals
- **Four Clear Categories**:
  1. **Application & System**: Software updates, Spell Check Language, Content & Maturity (18+ themes).
  2. **Chat Behavior & Display**: "My messages on the right", "Follow streaming replies".
  3. **Default Prompts & Instructions** (Option A: Stacked Cards): Fallback 1:1 system prompt, Group system prompt, Global prompt additions (Additional system instructions, Additional post-history instructions).
  4. **About & License**: App version, AGPL-3.0 license statement, and repository action links.
- **Card-Contained Visual Hierarchy**: Group related settings inside standard rounded cards (`AppColors.cardOf(context)`) with subtle borders (`AppColors.borderOf(context)`), eliminating floating orphan controls.
- **Typographic Scale & Role Discipline**:
  - Category titles: 16px Bold amber (`AppColors.porchAmberOf(context)`).
  - Slot/Card subheadings: 14px SemiBold primary text (`AppColors.textPrimary(context)`).
  - Control labels: 14px Medium (`bodyMedium`).
  - Descriptions/subtitles: 12px Regular (`bodySmall`, `AppColors.textSecondary(context)`, line-height 1.45).
  - Macro tokens (`{{char}}`, `{{user}}`): Monospace highlighted code badges.
- **Remove Redundant "Porch Life" Artifacts in General**: Replace the confusing `SectionHeader('Porch Life')` and the obsolete `PorchLifePointerCard` with a clearly labeled "Content & Maturity" switch for 18+ themes inside the Application & System category.
- **Code Cleanliness & Size Law**: Keep `general_tab.dart` under 200 lines by extracting cohesive modular section widgets into `lib/ui/settings/tabs/general_tab/`.

### Non-Goals
- Migrating chat display controls out of General into the Appearance tab (explicitly deferred by user; keeping in General).
- Redesigning the web companion's General section (explicitly deferred by user in this conversation per CLAUDE.md parity rule; web remains functionally intact and passes all parity tests).
- Altering the backend storage schema, Drift tables, or preferences keys for any settings.
- Changing the underlying behavior or transport of system prompt evaluation, group chat rules, or prompt macro resolution.

### Anti-Goals
- Adding complex multi-step accordions or hiding prompt textareas behind tabs (user explicitly rejected Option B in favor of Option A: vertical stacked cards).
- Introducing hardcoded hex colors or non-theme-safe colors (must strictly adhere to `AppColors.*Of(context)` and `AppPalette`).
- Breaking any `dartMarker` in `docs/design/settings-parity-manifest.json`.

---

## 3. Constraints & Architectural Rules

1. **CLAUDE.md Engineering Laws**:
   - **Size Law**: Every handwritten Dart file in `lib/` must remain strictly under 500 lines (`god_file_ratchet_test`).
   - **Theme Lint**: Zero raw `Colors.*` in UI code. All colors must read `AppColors.*Of(context)` or `AppPalette`.
   - **No Sync I/O**: No sync file access in UI widgets (`io-lint`).
   - **Dialogs**: Any dialogs must open through `showWarmDialog`.
   - **Desktop ↔ Web Parity**: Desktop settings must have their web twin in `web_ui/`. `docs/design/settings-parity-manifest.json` tracks each setting.
2. **Settings Parity Manifest (`docs/design/settings-parity-manifest.json`)**:
   The following markers must remain satisfied by `lib/ui/settings/tabs/general_tab.dart`:
   - `"My messages on the right"`
   - `"Follow streaming replies"`
   - `"SpellCheckLanguageRow"`
   - `"Fallback system prompt"`
   - `"Porch Life"` (marker retained for parity guard)
   - `"About & License"` (marker retained for parity guard)
3. **Existing Widget Tests**:
   - `test/ui/settings/general_tab_preset_chip_test.dart` expects to find `Reset to built-in` and preset chips.
   - `test/ui/settings/general_tab_saved_prompt_label_test.dart` expects `DropdownButtonFormField<String>` for the prompt slot.

---

## 4. Approaches Considered

### Prompt Layout:
- **Approach 1 (Option B - Segmented/Tabbed Prompt Selector)**: Group all prompts under a single card with segmented buttons (`[ 1:1 Fallback | Group Chats | Global Additions ]`).
  - *Trade-off*: Compact vertical footprint, but conceals important global instructions behind clicks, making it harder for users to realize global additions are active.
  - *Decision*: Rejected by user.
- **Approach 2 (Option A - Vertical Stacked Cards)**: Keep Fallback 1:1, Group Chat, and Global Additions in a clean vertical flow with clear subheadings, distinct card wells, and formatted macro tags.
  - *Trade-off*: Longer page height, but zero hidden state; users see exactly what prompts and additions are active simultaneously.
  - *Decision*: **Selected and locked by user.**

### Container Architecture:
- **Approach A (Flat list with dividers)**: Just add section headers and divider lines without wrapping cards.
  - *Trade-off*: Leaves controls feeling loose on wide desktop screens (400px–1440px wide).
- **Approach B (Grouped Card Wells - `SettingsGroupCard`)**: Enclose each logical category in a styled container card (`AppColors.cardOf(context)`) with a subtle 1px border (`AppColors.borderOf(context)`) and internal hairline dividers between items.
  - *Trade-off*: Clean, modern iOS/macOS/Material 3 settings aesthetic, clear visual grouping, excellent scannability.
  - *Decision*: **Selected.**

---

## 5. Detailed Component & UI Specification

### 5.1 Category 1: Application & System
- **Header**: `SectionHeader('Application & System')` (16px bold amber).
- **Container**: `SettingsGroupCard`.
- **Items**:
  1. **Software Updates** (`UpdateService.isSupported`):
     - Auto-check for updates toggle switch.
     - Inline action row: "Check for Updates Now" button with progress indicator and last status.
  2. **Hairline Divider**.
  3. **Spell Check Language**:
     - `SpellCheckLanguageRow` refactored to use standard typography: 14px Medium title, 12px Regular `textSecondary` subtitle, 220px `StyledDropdown`.
  4. **Hairline Divider**.
  5. **Content & Maturity (18+ Themes)**:
     - Title: "18+ themes"
     - Subtitle: "Unlocks adult features across the app, including the After Dark group in Porch Life and intimate preferences in the character creator. Turning off hides these features without erasing saved data."
     - Trailing: Switch bound to `storageService.realismSettings.adultThemesEnabled`.
     - *Note*: Includes retained parity marker comment `// Porch Life parity marker` so CI parity tests remain green.

### 5.2 Category 2: Chat Behavior & Display
- **Header**: `SectionHeader('Chat Behavior & Display')` (16px bold amber).
- **Container**: `SettingsGroupCard`.
- **Items**:
  1. **Message Alignment**:
     - Title: "My messages on the right"
     - Subtitle: "When enabled, your messages align to the right with your avatar on the right edge. When disabled, messages sit on the left alongside character replies."
     - Trailing: Switch bound to `storageService.realismSettings.userMessagesOnRight`.
  2. **Hairline Divider**.
  3. **Auto-Scroll Behavior**:
     - Title: "Follow streaming replies"
     - Subtitle: "Keep the chat pinned to newest words while a reply generates, as long as you are at the bottom. Scrolling up pauses auto-follow."
     - Trailing: Switch bound to `storageService.uiSettings.followStreamingReplies`.

### 5.3 Category 3: Default Prompts & Instructions (Option A)
- **Header**: `SectionHeader('Default Prompts & Instructions')` (16px bold amber).
- **Introductory Helper**:
  - Text: "Base prompts and system instructions used when characters or groups do not specify their own."
  - Macro Badges: Inline pill badges displaying `{{char}}` and `{{user}}` with explanatory tooltip/label.
- **Stacked Card Architecture**:
  Rather than cramming three large form systems into a single mega-card, Category 3 renders **3 distinct stacked sub-cards** under the category header, separated by standard 16px spacing. Each card represents a distinct prompt scope:
  1. **Fallback System Prompt Card (1:1 Chats)**:
     - Enclosed in `AppColors.cardOf(context)` container with 1px border.
     - Header: 14px SemiBold `textPrimary` title ("Fallback system prompt") + status pill badge (`_SlotBadge`).
     - Helper text: 12px Regular `textSecondary`.
     - Controls: Saved prompt dropdown, delete action, multi-line editor (3–6 lines), and action buttons ("Save as new...", "Reset to built-in").
  2. **Group Chat System Prompt Card**:
     - Enclosed in matching card container.
     - Header: 14px SemiBold `textPrimary` title ("Group system prompt") + status pill badge.
     - Helper text: 12px Regular `textSecondary`.
     - Controls: Saved prompt dropdown, delete action, multi-line editor, and action buttons.
  3. **Global Prompt Additions Card**:
     - Enclosed in matching card container.
     - Header: 14px SemiBold `textPrimary` title ("Global prompt additions").
     - Subtitle: 12px Regular `textSecondary` ("Appended to all prompts. Both fields support `{{char}}` and `{{user}}` macros.").
     - Inputs: "Additional system instructions" and "Additional post-history instructions" with clear helper labels.

### 5.4 Category 4: About & License
- **Header**: `SectionHeader('About & License')` (16px bold amber).
- **Component**: Refactored `AboutLicenseCard`:
  - App title & version: `Front Porch AI v$appVersion` (14px Bold `textPrimary`).
  - License description: AGPL-3.0 explanation (12px Regular `textSecondary`, line-height 1.45).
  - Action chips: "Source code" (GitHub link) and "Report a license violation" (GitHub issues link).

---

## 6. What's Left to the Builder

- Creating the reusable `SettingsGroupCard` widget in `lib/ui/settings/widgets/settings_group_card.dart`.
- Extracting the sections into cleanly scoped Dart files under `lib/ui/settings/tabs/general_tab/`:
  - `app_system_section.dart`
  - `chat_behavior_section.dart`
  - `prompts_section.dart`
- Updating `general_tab.dart` to assemble the 4 sections while preserving parity markers.
- Verifying all widget tests, hygiene tests, and analyzer checks pass cleanly.
