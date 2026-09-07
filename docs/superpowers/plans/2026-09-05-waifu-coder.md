# Waifu Coder (waifu coding) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the complete Waifu Coder feature on `feat/mcp-client` / PR #233 for one squash into Rawhide.

**Architecture:** Island under `lib/services/waifu/` + `lib/ui/waifu/`. No `ChatService` construction, Realism/Needs/Journal ticks, web Waifu page, OpenCode/Bun process, or stdio MCP. The in-process tool loop owns file/patch/bash tools, a persisted Folder-jail (default) vs Whole-disk scope, ruthless shared hard-denies, bounded nested tasks, and character voice.

**Tech Stack:** Flutter/Dart, Provider, `dart:io` Directory walker, existing `LLMService.generateWithTools`, AppColors / porch amber, Drift only if slice G needs a table (JSON under the data dir is allowed).

**Spec:** `docs/superpowers/specs/2026-09-05-waifu-coding-design.md`

## Global Constraints

- Work only on `feat/mcp-client`; PR base remains Rawhide. Do not merge.
- Every Dart file under 500 lines. No `lib/` file may reach 1,000.
- Every new guard is proven red then green. Existing assertions that described the retired single-scope behavior are intentionally rewritten under the signed dual-scope decision.
- `HomeModeToggle` constructor must keep `showStories` / `onShowChats` / `onShowStories` so `test/ui/pages/home/home_grid_toolbar_overflow_test.dart` still compiles. Waifu Coder is an **additive** optional (`showWaifu`, `onShowWaifu`).
- AppColors / `formMasterAccent` / `porchAmberOf` / `onChaosAccent`. No `Colors.blueAccent`. No hard-coded `Color(0xFF…)`.
- Barrel imports. `dart format` only files you touched. Never `dart format .`.
- No `web_ui/` Waifu Coder page (maintainer deferred). No OpenCode/Bun/ACP spawn. No stdio MCP. No silent LSP zoo.
- Honesty gate copy is blunt (Claude Code / Grok Build / OpenCode; never critical codebases). Advanced audience — no kindergarten copy.
- `FilePicker` is forbidden on the folder step. In-app `Directory.list` only.
- Sync I/O is banned in `lib/ui/**` `build` paths.
- Web parity N/A this conversation. Path-complete chat matrix N/A (separate pipeline).
- Commit and push each logical body to `feat/mcp-client`; never open a second PR or merge #233.

---

## File map (slice A)

**Create:**
- `lib/services/waifu/waifu.dart` — barrel
- `lib/services/waifu/waifu_honesty.dart` — honesty copy + checkbox label constants
- `lib/services/waifu/waifu_coworker_prompt.dart` — `buildWaifuCoworkerPrompt(CharacterCard)`
- `lib/services/waifu/waifu_sit_down.dart` — `WaifuMode`, `waifuCanSitDown(...)`
- `lib/services/waifu/waifu_folder_listing.dart` — async directory listing + project markers
- `lib/services/waifu/waifu_session.dart` — in-memory session (folder, coworker, mode, transcript)
- `lib/ui/waifu/waifu.dart` — barrel
- `lib/ui/waifu/waifu_home_view.dart` — third home pane + Sit down CTA
- `lib/ui/waifu/waifu_wizard_page.dart` — 3-step Create-Character chrome
- `lib/ui/waifu/waifu_wizard_project_step.dart` — folder walker
- `lib/ui/waifu/waifu_wizard_coworker_step.dart` — character pick
- `lib/ui/waifu/waifu_wizard_sit_down_step.dart` — recap + honesty + mode
- `lib/ui/waifu/waifu_page.dart` — empty session chrome (portrait, composer, no loop)
- `test/services/waifu/waifu_coworker_prompt_test.dart`
- `test/services/waifu/waifu_sit_down_test.dart`
- `test/services/waifu/waifu_folder_listing_test.dart`
- `test/ui/waifu/waifu_home_toggle_test.dart`
- `test/ui/waifu/waifu_wizard_test.dart`
- `test/ui/waifu/waifu_session_chrome_test.dart`

**Modify:**
- `lib/ui/pages/home/widgets/home_mode_toggle.dart` — third Waifu Coder button; keep old named args
- `lib/ui/pages/home_page.dart` — `_homeMode` enum; Waifu Coder pane
- `lib/ui/pages/home/home_page_chrome.dart` — wire Waifu Coder callback
- `.claude/changelog.md`, `docs/Rawhide.md`

**Do not modify:** any existing test, `web_ui/`, `ChatService`, `pubspec.yaml`, `database.dart`.

---

### Task 1: Pure prompt + honesty + sit-down gate

**Files:**
- Create: `lib/services/waifu/waifu_honesty.dart`
- Create: `lib/services/waifu/waifu_coworker_prompt.dart`
- Create: `lib/services/waifu/waifu_sit_down.dart`
- Create: `lib/services/waifu/waifu.dart`
- Test: `test/services/waifu/waifu_coworker_prompt_test.dart`
- Test: `test/services/waifu/waifu_sit_down_test.dart`

**Interfaces:**
- Consumes: `CharacterCard` (`name`, `description`, `personality`, `systemPrompt`, `mesExample`, `scenario`, `frontPorchExtensions`)
- Produces:
  - `waifuHonestyBody(pathMode)` / `waifuHonestyCheckbox(pathMode)` / `kWaifuPreamble`
  - `String buildWaifuCoworkerPrompt(CharacterCard card)`
  - `enum WaifuMode { plan, build, yolo }`
  - `bool waifuCanSitDown({required bool honestyAccepted, required bool toolsSupported, required bool hasFolder, required bool hasCoworker})`

- [ ] **Step 1: Write the failing tests** (see files below in this plan).
- [ ] **Step 2: Run them — expect missing-symbol / compile fail.**
- [ ] **Step 3: Minimal implementation.**
- [ ] **Step 4: Tests pass.**
- [ ] **Step 5: Commit** `feat(waifu): coworker prompt, honesty copy, sit-down gate`

Prompt rules (spec §5): include name, description, personality, systemPrompt if non-empty, truncated mesExample as style hint, plus `kWaifuPreamble`. Must **not** contain `scenario`, lorebook text, firstMessage, needs/occupation, or the words of a scenario unique string used in the test (`SCENARIO_MUST_NOT_APPEAR`).

Honesty names Claude Code, Grok Build, OpenCode, and the critical-codebase law. Folder-jail copy says it is the safer default and confines paths. Whole-disk copy says the folder is only a starting porch and explicitly acknowledges access elsewhere. Changing scope clears acceptance.

`waifuCanSitDown` is true only when all four flags are true. Tools-unsupported is a hard block even if the box is ticked.

---

### Task 2: Folder listing (no FilePicker)

**Files:**
- Create: `lib/services/waifu/waifu_folder_listing.dart`
- Test: `test/services/waifu/waifu_folder_listing_test.dart`

**Produces:**
```dart
class WaifuDirEntry { final String name; final String path; }
class WaifuFolderListing {
  final String path;
  final String? parentPath;
  final List<WaifuDirEntry> directories;
  final List<String> projectHints; // markers present in this folder
}
const kWaifuProjectMarkers = ['pubspec.yaml', '.git', 'package.json', 'Cargo.toml', 'project.godot'];
Future<WaifuFolderListing> listWaifuDirectory(String path);
String waifuDefaultStartPath();
```

- [ ] Failing test: temp dir with a child folder + `pubspec.yaml` → listing includes child, `projectHints` contains `pubspec.yaml`, `parentPath` is the parent.
- [ ] Listing must not throw on a missing path; return empty directories.
- [ ] `waifuDefaultStartPath` uses `HOME` / `USERPROFILE` / systemTemp — never a hard-coded `/Users/`.
- [ ] Implement with `Directory.list(followLinks: false)`. Skip `Link` entries.
- [ ] Commit `feat(waifu): in-app folder listing`

---

### Task 3: Home toggle + Waifu Coder home pane

**Files:**
- Modify: `lib/ui/pages/home/widgets/home_mode_toggle.dart`
- Modify: `lib/ui/pages/home_page.dart`
- Modify: `lib/ui/pages/home/home_page_chrome.dart`
- Create: `lib/ui/waifu/waifu_home_view.dart`
- Create: `lib/ui/waifu/waifu.dart`
- Test: `test/ui/waifu/waifu_home_toggle_test.dart`

Keep constructor:

```dart
const HomeModeToggle({
  super.key,
  required this.showStories,
  required this.onShowChats,
  required this.onShowStories,
  this.showWaifu = false,
  this.onShowWaifu,
});
```

Always render a third `_ModeButton(label: 'Waifu Coder', icon: Icons.waifu)`. If `onShowWaifu` is null, `onTap` is empty (overflow test still compiles and layout stays icon-safe). Raise `labeledMinWidth` to `400` so three labels drop to icons before the 360px overflow case.

Home state: replace `bool _showStories` with `enum HomeMode { chats, stories, waifu }` stored on `_HomePageState` as `_homeMode`. Stories branch unchanged. New Waifu Coder branch wraps `WaifuHomeView` the same way Stories wraps `StoryHomeView` (toggle bar + status bar). Waifu Coder is reachable on an empty character library.

- [ ] Test: `HomeModeToggle` shows `Waifu Coder`. Tapping it calls `onShowWaifu`.
- [ ] Commit `feat(waifu): home mode sibling of Porch Stories`

---

### Task 4: Wizard (Project → Coworker → Sit down)

**Files:**
- Create: `lib/ui/waifu/waifu_wizard_page.dart`
- Create: `lib/ui/waifu/waifu_wizard_project_step.dart`
- Create: `lib/ui/waifu/waifu_wizard_coworker_step.dart`
- Create: `lib/ui/waifu/waifu_wizard_sit_down_step.dart`
- Create: `lib/services/waifu/waifu_session.dart`
- Test: `test/ui/waifu/waifu_wizard_test.dart`

Create-Character chrome: AppBar dots + labels + connecting lines, `AnimatedSwitcher` on `_currentStep` (0 Project, 1 Coworker, 2 Sit down), Back/Next at the bottom. Linear. No side menu.

Inject for tests:
- `List<CharacterCard> characters`
- `bool toolsSupported`
- `bool isLocalBackend`
- `String backendLabel`
- `String initialFolder` (temp dir)
- `void Function(WaifuSession session)? onSatDown`

Sit down Confirm (`key: Key('waifu-sit-down-confirm')`) is disabled until `waifuCanSitDown`. Checkbox `Key('waifu-honesty-checkbox')`. Scope cards are `Folder jail (safer default)` and `Whole-disk access`. Tools-unsupported remains a hard block. Yolo and MCP copy branch on scope and never claim a jail in Whole-disk mode.

Source of `waifu_wizard_project_step.dart` must not contain `FilePicker`.

- [ ] Widget tests covering: step labels, checkbox gate, tools block, FilePicker absent from that file.
- [ ] Commit `feat(waifu): sit-down wizard with honesty gate`

---

### Task 5: Empty session chrome

**Files:**
- Create: `lib/ui/waifu/waifu_page.dart`
- Test: `test/ui/waifu/waifu_session_chrome_test.dart`

Portrait + coworker name + folder basename + composer. Send appends a user bubble to the in-memory transcript and does **not** call an LLM. No Character State / Journal / Needs / Continue. No `ChatService` import in `lib/ui/waifu/` or `lib/services/waifu/`.

- [ ] Test finds coworker name, folder name, composer; `grep ChatService lib/services/waifu lib/ui/waifu` is empty.
- [ ] Commit `feat(waifu): empty session chrome (no loop yet)`
- [ ] Update `.claude/changelog.md` + `docs/Rawhide.md`

---

## Slices B–I (all ship in #233)

The implementation kept these contracts as reviewable internal slices, but the
complete set lands in the single #233 squash:

| Slice | Done when | Key types / tools |
|---|---|---|
| **B** | Send loops `generateWithTools`. Tools: read/edit/apply_patch/write/glob/grep. Folder jail or Whole-disk. 80-step fuse. Abort kills work. Work strip records writes. | `WaifuHarness`, `WaifuJail`, `WaifuPatch`, `WaifuLlm` |
| **C** | Plan/Build/Yolo. Plan blocks local + mutating MCP tools; Build asks; Yolo skips asks. Both scopes hard-deny secrets, env dumps, destructive Git, force-push, recursive roots/homes/parents/system wipes, format/device/find/permission bombs. | `WaifuPermissions` |
| **D** | `bash` cwd=root, scope-aware path preflight, scrubbed child environment, timeout + user Abort process kill. Undo/redo of her writes only. | `WaifuBash`, `WaifuUndo` |
| **E** | todos, question, @files, `/init` AGENTS.md, skill loader | `WaifuTodos`, `WaifuQuestion` |
| **F** | webfetch (no-redirect), FP websearch, opt-in HTTP MCP | existing MCP hub, not stdio |
| **G** | compaction, resume last waifu, title | JSON under data dir, not `messages` |
| **H** | Explore/General may delegate one more task layer; deepest worker stops. Scope and abort propagate through the tree. | after A–G |
| **I** | Language-help catalog, none pre-ticked, PATH first, pin+checksum, custom command, Yolo does not auto-open | after D |

Turn completion is two-axis: code-change wording requires a real
write/edit/apply_patch receipt, and successful tools require a non-generic
in-character spoken line. The harness preserves speech emitted beside tool
calls and issues bounded, tool-free voice retries instead of inserting “Done”
or “I could not work.”

Regen ruling (spec left a pick): **disabled** in v1. Continue control does not exist. A new send is a new loop.

---

## Hostile-review cadence (maintainer `/loop`)

After each slice commit, the next turn: (1) hostile self-review of that commit, (2) fix load-bearing holes, (3) only then start the next slice. Ledger: `.grok/waifu-loop/progress.md` (gitignored).
