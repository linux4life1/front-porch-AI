# General Settings UI/UX Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize Front Porch AI's General Settings page into 4 cohesive card-contained categories with a disciplined 2-level typographic hierarchy, modular sub-components, and 100% desktop/web parity test compliance.

**Architecture:** Extract General Settings from a monolithic `general_tab.dart` file into four focused section components under `lib/ui/settings/tabs/general_tab/` (`AppSystemSection`, `ChatBehaviorSection`, `PromptsSection`, `AboutLicenseCard`), unified by a reusable `SettingsGroupCard` container and a standard semantic typography scale (`AppColors`, `ThemeData.textTheme`).

**Tech Stack:** Flutter / Dart, Provider (`StorageService`, `UpdateService`), Material 3 theming (`AppColors`, `AppPalette`, `AppCorners`), Flutter test harness.

**Spec:** `docs/superpowers/specs/2026-11-09-general-settings-redesign.md`

## Global Constraints

- **Size Law:** Handwritten `lib/` Dart files must stay strictly under 500 lines (`god_file_ratchet_test`).
- **Theme Lint:** Zero raw `Colors.*` in UI code; consume `AppColors.*Of(context)` and `AppPalette` exclusively (`theme-lint`).
- **No Sync I/O:** No sync I/O in widget `build` or render trees (`io-lint`).
- **Dialogs:** Dialogs open through `showWarmDialog` (`raw_dialogs_ratchet_test`).
- **Parity Manifest:** `docs/design/settings-parity-manifest.json` markers must remain satisfied by the files they pin (`settings_parity_manifest_test.dart`).
- **Web Parity:** Web redesign is deferred per maintainer direction; web tests (`SettingsPage.parity.test.tsx`) must remain untouched and green.

## Review Focus

1. **Light/Dark theme readability:** Section headers and subtitles in `SettingsGroupCard` and `PromptSlotCard` must remain legible in both light and dark themes without low-contrast unselected text.
2. **Narrow viewport resilience (< 400px):** Setting rows (e.g. Update button, Spell Check dropdown, and prompt action buttons) must wrap cleanly without `RenderFlex` overflow errors.
3. **Parity guard path resolution:** Modifying file paths in `docs/design/settings-parity-manifest.json` must exactly match the extracted Dart files and pass `settings_parity_manifest_test.dart`.
4. **Prompt Controller state preservation:** Refactoring `PromptSlotCard` must not sever or desynchronize `systemPromptController` passed from `SettingsPage` to `GeneralTab`.
5. **Preset reset menu visibility:** The "Reset to built-in" button and dropdown in `PromptSlotCard` must remain discoverable and responsive to taps during widget tests.

---

### Task 1: Create Reusable `SettingsGroupCard` Widget

**Files:**
- Create: `lib/ui/settings/widgets/settings_group_card.dart`
- Modify: `lib/ui/settings/widgets/widgets.dart`
- Test: `test/ui/settings/settings_group_card_test.dart`

**Interfaces:**
- Produces: `SettingsGroupCard({Key? key, required List<Widget> children, EdgeInsetsGeometry padding, EdgeInsetsGeometry margin, bool showDividers = true})`

- [ ] **Step 1: Write the failing widget test**

```dart
// test/ui/settings/settings_group_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/settings/widgets/settings_group_card.dart';

void main() {
  testWidgets('SettingsGroupCard renders children with hairline dividers', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SettingsGroupCard(
            children: [
              Text('Item 1'),
              Text('Item 2'),
              Text('Item 3'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Item 1'), findsOneWidget);
    expect(find.text('Item 2'), findsOneWidget);
    expect(find.text('Item 3'), findsOneWidget);
    expect(find.byType(Divider), findsNWidgets(2));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/settings/settings_group_card_test.dart`  
Expected: FAIL with compilation error (file not found)

- [ ] **Step 3: Implement `SettingsGroupCard`**

Implement in `lib/ui/settings/widgets/settings_group_card.dart`:
- Container with `AppColors.cardOf(context)` background, 1px `AppColors.borderOf(context)` border, and 12px border radius.
- Injects `Divider(height: 1, thickness: 1, color: AppColors.borderOf(context).withValues(alpha: 0.5))` between children when `showDividers` is true.
- Export `settings_group_card.dart` in `lib/ui/settings/widgets/widgets.dart`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/settings/settings_group_card_test.dart`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/ui/settings/widgets/settings_group_card.dart lib/ui/settings/widgets/widgets.dart test/ui/settings/settings_group_card_test.dart
git commit -m "feat(ui): add reusable SettingsGroupCard container widget"
```

---

### Task 2: Create `ChatBehaviorSection` Component

**Files:**
- Create: `lib/ui/settings/tabs/general_tab/chat_behavior_section.dart`
- Modify: `lib/ui/settings/tabs/general_tab/general_tab.dart` (barrel export)
- Test: `test/ui/settings/general_chat_behavior_section_test.dart`

**Interfaces:**
- Consumes: `SettingsGroupCard`, `SectionHeader`, `StorageService` (`realismSettings.userMessagesOnRight`, `uiSettings.followStreamingReplies`)
- Produces: `ChatBehaviorSection({Key? key})`
- Pinned Parity Markers: `"My messages on the right"`, `"Follow streaming replies"`

- [ ] **Step 1: Write the failing widget test**

```dart
// test/ui/settings/general_chat_behavior_section_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/settings/tabs/general_tab/chat_behavior_section.dart';

class _FakeStorage extends ChangeNotifier implements StorageService {
  @override
  final RealismSettings realismSettings = RealismSettings();
  @override
  final UiSettings uiSettings = UiSettings();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('ChatBehaviorSection renders message side and streaming toggles', (tester) async {
    final storage = _FakeStorage();
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: const MaterialApp(
          home: Scaffold(body: ChatBehaviorSection()),
        ),
      ),
    );

    expect(find.text('Chat Behavior & Display'), findsOneWidget);
    expect(find.text('My messages on the right'), findsOneWidget);
    expect(find.text('Follow streaming replies'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/settings/general_chat_behavior_section_test.dart`  
Expected: FAIL with compilation error

- [ ] **Step 3: Implement `ChatBehaviorSection`**

Implement in `lib/ui/settings/tabs/general_tab/chat_behavior_section.dart`:
- `SectionHeader('Chat Behavior & Display')`
- `SettingsGroupCard`:
  - `SwitchListTile` for `userMessagesOnRight` with `key: const ValueKey('user-messages-on-right')`. Title in `bodyMedium` (14px SemiBold `textPrimary`), subtitle in `bodySmall` (12px `textSecondary`, line-height 1.45).
  - `SwitchListTile` for `followStreamingReplies`. Matching typography.
- Export in `lib/ui/settings/tabs/general_tab/general_tab.dart`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/settings/general_chat_behavior_section_test.dart`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/ui/settings/tabs/general_tab/chat_behavior_section.dart lib/ui/settings/tabs/general_tab/general_tab.dart test/ui/settings/general_chat_behavior_section_test.dart
git commit -m "feat(settings): extract ChatBehaviorSection with unified card and typography"
```

---

### Task 3: Create `AppSystemSection` Component

**Files:**
- Create: `lib/ui/settings/tabs/general_tab/app_system_section.dart`
- Modify: `lib/ui/settings/widgets/spell_check_language_row.dart`
- Modify: `lib/ui/settings/tabs/general_tab/general_tab.dart` (barrel export)
- Test: `test/ui/settings/general_app_system_section_test.dart`

**Interfaces:**
- Consumes: `SettingsGroupCard`, `SectionHeader`, `SpellCheckLanguageRow`, `StorageService`, `UpdateService`
- Produces: `AppSystemSection({Key? key})`
- Pinned Parity Markers: `"SpellCheckLanguageRow"`, `"Porch Life"` (18+ themes marker)

- [ ] **Step 1: Write the failing widget test**

```dart
// test/ui/settings/general_app_system_section_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/settings/tabs/general_tab/app_system_section.dart';

class _FakeStorage extends ChangeNotifier implements StorageService {
  @override
  final RealismSettings realismSettings = RealismSettings();
  @override
  String get spellCheckLanguage => kSpellCheckOff;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('AppSystemSection renders updates, spellcheck, and 18+ themes', (tester) async {
    final storage = _FakeStorage();
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: const MaterialApp(
          home: Scaffold(body: AppSystemSection()),
        ),
      ),
    );

    expect(find.text('Application & System'), findsOneWidget);
    expect(find.text('Spell Check Language'), findsOneWidget);
    expect(find.text('18+ themes'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/settings/general_app_system_section_test.dart`  
Expected: FAIL with compilation error

- [ ] **Step 3: Refactor `SpellCheckLanguageRow` typography & Implement `AppSystemSection`**

In `lib/ui/settings/widgets/spell_check_language_row.dart`:
- Change title style to `TextStyle(color: AppColors.textPrimary(context), fontSize: 14, fontWeight: FontWeight.w600)`.
- Change subtitle style to `TextStyle(color: AppColors.textSecondary(context), fontSize: 12, height: 1.4)`.

In `lib/ui/settings/tabs/general_tab/app_system_section.dart`:
- `SectionHeader('Application & System')`
- `SettingsGroupCard`:
  - `UpdateService` row (if supported) + Check for Updates button.
  - `SpellCheckLanguageRow()`
  - `SwitchListTile` for `adultThemesEnabled` with 14px SemiBold title, 12px `textSecondary` subtitle, calling `offerAfterglowInExistingChats`.
  - Retain marker comment `// Porch Life` for parity manifest verification.
- Export in `lib/ui/settings/tabs/general_tab/general_tab.dart`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/settings/general_app_system_section_test.dart`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/ui/settings/tabs/general_tab/app_system_section.dart lib/ui/settings/widgets/spell_check_language_row.dart lib/ui/settings/tabs/general_tab/general_tab.dart test/ui/settings/general_app_system_section_test.dart
git commit -m "feat(settings): extract AppSystemSection with typography alignment"
```

---

### Task 4: Refactor `PromptSlotCard` and `GlobalPromptAdditions` Typography & Visual Card Hierarchy

**Files:**
- Modify: `lib/ui/settings/widgets/prompt_slot_card.dart`
- Modify: `lib/ui/settings/widgets/global_prompt_additions.dart`
- Create: `lib/ui/settings/tabs/general_tab/prompts_section.dart`
- Modify: `lib/ui/settings/tabs/general_tab/general_tab.dart` (barrel export)
- Test: `test/ui/settings/general_prompts_section_test.dart`

**Interfaces:**
- Consumes: `PromptSlotCard`, `GroupSystemPromptField`, `GlobalPromptAdditions`
- Produces: `PromptsSection({Key? key, required TextEditingController systemPromptController})`
- Pinned Parity Markers: `"Fallback system prompt"`, `"Group system prompt"`, `"Additional system instructions"`, `"Additional post-history instructions"`

- [ ] **Step 1: Write the failing widget test**

```dart
// test/ui/settings/general_prompts_section_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/settings/tabs/general_tab/prompts_section.dart';

class _FakeStorage extends ChangeNotifier implements StorageService {
  @override
  final GenerationSettings generationSettings = GenerationSettings();
  @override
  final PresetSettings presetSettings = PresetSettings();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('PromptsSection renders category header, badges, and 3 stacked cards', (tester) async {
    final storage = _FakeStorage();
    final controller = TextEditingController();
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PromptsSection(systemPromptController: controller),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Default Prompts & Instructions'), findsOneWidget);
    expect(find.text('{{char}}'), findsAtLeastNWidgets(1));
    expect(find.text('{{user}}'), findsAtLeastNWidgets(1));
    expect(find.text('Fallback system prompt'), findsAtLeastNWidgets(1));
    expect(find.text('Group system prompt'), findsAtLeastNWidgets(1));
    expect(find.text('Global prompt additions'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/settings/general_prompts_section_test.dart`  
Expected: FAIL with compilation error

- [ ] **Step 3: Refactor `PromptSlotCard`, `GlobalPromptAdditions`, and Implement `PromptsSection`**

In `lib/ui/settings/widgets/prompt_slot_card.dart`:
- Replace internal `SectionHeader(widget.title)` with `Text(widget.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary(context)))`.
- Wrap the entire slot content in a container card (`AppColors.cardOf(context)`, 1px border, 12px radius, 16px padding).
- Update helper copy style to `TextStyle(fontSize: 12, color: AppColors.textSecondary(context), height: 1.4)`.

In `lib/ui/settings/widgets/global_prompt_additions.dart`:
- Replace `SectionHeader('Global prompt additions')` with `Text('Global prompt additions', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary(context)))`.
- Wrap in matching card container (`AppColors.cardOf(context)`).
- Update helper text to 12px `textSecondary`.

In `lib/ui/settings/tabs/general_tab/prompts_section.dart`:
- `SectionHeader('Default Prompts & Instructions')`
- Helper paragraph with inline monospace chips for `{{char}}` and `{{user}}`.
- 3 stacked cards: `PromptSlotCard(slot: PromptSlot.oneToOne)`, `GroupSystemPromptField()`, `GlobalPromptAdditions()`, separated by 16px vertical spacing.
- Export in `lib/ui/settings/tabs/general_tab/general_tab.dart`.

- [ ] **Step 4: Run test to verify it passes and existing prompt tests pass**

Run: `flutter test test/ui/settings/general_prompts_section_test.dart`  
Run: `flutter test test/ui/settings/general_tab_preset_chip_test.dart`  
Run: `flutter test test/ui/settings/general_tab_saved_prompt_label_test.dart`  
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add lib/ui/settings/widgets/prompt_slot_card.dart lib/ui/settings/widgets/global_prompt_additions.dart lib/ui/settings/tabs/general_tab/prompts_section.dart lib/ui/settings/tabs/general_tab/general_tab.dart test/ui/settings/general_prompts_section_test.dart
git commit -m "feat(settings): refine PromptSlotCard and extract PromptsSection with macro badges"
```

---

### Task 5: Refactor `AboutLicenseCard` and Assemble `GeneralTab`

**Files:**
- Modify: `lib/ui/settings/tabs/general_tab/about_license_card.dart`
- Modify: `lib/ui/settings/tabs/general_tab.dart`
- Modify: `docs/design/settings-parity-manifest.json` (ensure all mapped files and markers match)
- Test: `test/hygiene/settings_parity_manifest_test.dart`
- Test: `test/ui/settings/general_tab_preset_chip_test.dart`

**Interfaces:**
- Consumes: `AppSystemSection`, `ChatBehaviorSection`, `PromptsSection`, `AboutLicenseCard`
- Produces: `GeneralTab({Key? key, required TextEditingController systemPromptController})`

- [ ] **Step 1: Refactor `AboutLicenseCard` typography**

In `lib/ui/settings/tabs/general_tab/about_license_card.dart`:
- Set version title style: `TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary(context))`.
- Set AGPL description style: `TextStyle(fontSize: 12, color: AppColors.textSecondary(context), height: 1.45)`.
- Use `AppCorners.standard` border radius.

- [ ] **Step 2: Assemble `GeneralTab` coordinator in `lib/ui/settings/tabs/general_tab.dart`**

Replace monolithic contents in `lib/ui/settings/tabs/general_tab.dart` with:
- Clean coordinator layout assembling:
  1. `AppSystemSection()`
  2. `const SizedBox(height: 28)`
  3. `ChatBehaviorSection()`
  4. `const SizedBox(height: 28)`
  5. `PromptsSection(systemPromptController: systemPromptController)`
  6. `const SizedBox(height: 28)`
  7. `SectionHeader('About & License')`
  8. `const SizedBox(height: 8)`
  9. `AboutLicenseCard()`
- Include necessary parity markers/comments so `settings_parity_manifest_test.dart` and `docs/design/settings-parity-manifest.json` remain in complete agreement.
- Ensure `general_tab.dart` is under 120 lines total.

- [ ] **Step 3: Update `docs/design/settings-parity-manifest.json` if paths moved**

Verify each control in `docs/design/settings-parity-manifest.json` pointing to `general_tab.dart`:
- `userMessagesOnRight`: `"dart": "lib/ui/settings/tabs/general_tab/chat_behavior_section.dart"` (or keep pointer in `general_tab.dart`)
- `followStreamingReplies`: `"dart": "lib/ui/settings/tabs/general_tab/chat_behavior_section.dart"`
- `spellCheckLanguage`: `"dart": "lib/ui/settings/tabs/general_tab/app_system_section.dart"`
- `systemPrompt`: `"dart": "lib/ui/settings/tabs/general_tab/prompts_section.dart"`
- `porchLife`: `"dart": "lib/ui/settings/tabs/general_tab/app_system_section.dart"`
- `aboutLicense`: `"dart": "lib/ui/settings/tabs/general_tab.dart"` (or `about_license_card.dart`)

- [ ] **Step 4: Run hygiene and parity tests**

Run: `flutter test test/hygiene/settings_parity_manifest_test.dart`  
Run: `flutter test test/ui/settings/general_tab_preset_chip_test.dart`  
Run: `flutter test test/ui/settings/general_tab_saved_prompt_label_test.dart`  
Run: `flutter analyze lib/ui/settings/`  
Expected: ALL PASS with zero analyzer warnings

- [ ] **Step 5: Commit**

```bash
git add lib/ui/settings/tabs/general_tab/about_license_card.dart lib/ui/settings/tabs/general_tab.dart docs/design/settings-parity-manifest.json
git commit -m "feat(settings): assemble redesigned GeneralTab with card categories and verified parity"
```

---

### Task 6: Full Verification & God-File Ratchet Audit

**Files:**
- Test: All tests in `test/ui/settings/`
- Test: `test/hygiene/god_file_ratchet_test.dart`
- Test: `test/hygiene/theme_lint_test.dart` (or analyze)

- [ ] **Step 1: Run full unit & hygiene test sweep**

Run:
```bash
flutter test test/ui/settings/
flutter test test/hygiene/god_file_ratchet_test.dart
flutter test test/hygiene/settings_parity_manifest_test.dart
flutter analyze lib/ui/settings/
```
Expected: ALL PASS with 0 failures and 0 warnings.

- [ ] **Step 2: Commit any final formatting or test touchups**

```bash
git status
# If clean, proceed; otherwise commit with "chore: formatting and final hygiene pass"
```
