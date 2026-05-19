# Keyboard Shortcuts

---

## Table of Contents

1. [Chat Shortcuts](#chat-shortcuts)
2. [Navigation Shortcuts](#navigation-shortcuts)
3. [Voice Shortcuts](#voice-shortcuts)
4. [Editor Shortcuts](#editor-shortcuts)
5. [Platform Notes](#platform-notes)

---

## Chat Shortcuts

The only custom keyboard handling implemented in the chat composer (see `lib/ui/pages/chat_page.dart:199`):

| Shortcut            | Action |
|---------------------|--------|
| `Enter`             | Send the current message (when the chat input field has focus and is not empty; generation must not be in progress) |
| `Shift + Enter`     | Insert a literal newline in the message input (prevents accidental send) |

Other actions (Regenerate, swipe left/right between alternate responses, Director Mode toggle, open Chat Settings, Voice input) are performed via on-screen buttons and icons in the chat UI — no dedicated global hotkeys are wired for them. Standard OS clipboard and editing keys (Copy/Paste/Undo) work inside the input field.

---

## Navigation Shortcuts

No custom global navigation hotkeys are implemented (sidebar selection is pointer-driven via `AppState.setIndex` in `lib/ui/layout/main_layout.dart` and `lib/ui/widgets/sidebar.dart`).

| Shortcut          | Action |
|-------------------|--------|
| Tab / Shift+Tab   | Move keyboard focus between UI controls (standard Flutter behavior) |
| (none)            | Direct sidebar page switching requires mouse click |

Use the left sidebar to switch between Home, Create Character, Model Manager, Settings, User Persona, and Worlds. The AI Character Creator opens in its own window.

---

## Voice Shortcuts

No push-to-talk or voice-call hotkeys (Spacebar, etc.) are implemented. Voice features are controlled via the microphone icon in the chat input area (`SttService` + `record` package).

| Shortcut | Action |
|----------|--------|
| (none)   | Click the 🎤 mic icon to start/stop push-to-talk recording |
| (none)   | Use the Voice Call overlay (continuous mode) for hands-free conversation |

See Settings → Voice for STT engine configuration, silence threshold, and auto-send transcription.

---

## Editor Shortcuts

All character, story, and world editors use standard Flutter `TextField` / `TextFormField` widgets. No custom `Actions`/`Intent` or `SingleActivator` keyboard bindings are registered.

| Shortcut                        | Action |
|---------------------------------|--------|
| `Ctrl / ⌘ + C`                  | Copy selected text |
| `Ctrl / ⌘ + V`                  | Paste |
| `Ctrl / ⌘ + X`                  | Cut |
| `Ctrl / ⌘ + Z`                  | Undo |
| `Ctrl / ⌘ + Shift + Z`          | Redo |
| `Ctrl / ⌘ + A`                  | Select all |
| Arrow keys / Home / End / PgUp / PgDn | Standard text navigation and selection |
| `Enter`                         | Submit form (in character creator review step, etc.) |

Rich text formatting shortcuts (bold/italic) are not implemented; the editors are plain-text or Markdown-based.

---

## Platform Notes

- **macOS**: Use the `⌘ Command` key in place of `Ctrl` for all standard OS-level shortcuts (copy, paste, undo, select all, close window, etc.). The chat `Enter` / `Shift+Enter` handler works identically.
- **Windows / Linux**: Use the `Ctrl` key for the same operations.
- The app does not register system-wide global hotkeys (no `hotkey_manager` or similar). All shortcuts require the app window to be focused.
- On all platforms, `Esc` closes most dialogs (standard Material behavior).

For the most up-to-date behavior, the source of truth is the `onKeyEvent` handler on the chat `FocusNode` and Flutter's built-in text editing actions.

---

## Navigation Shortcuts

No custom global navigation hotkeys are implemented (sidebar selection is pointer-driven via `AppState.setIndex` in `lib/ui/layout/main_layout.dart` and `lib/ui/widgets/sidebar.dart`).

| Shortcut          | Action |
|-------------------|--------|
| Tab / Shift+Tab   | Move keyboard focus between UI controls (standard Flutter behavior) |
| (none)            | Direct sidebar page switching requires mouse click |

Use the left sidebar to switch between Home, Create Character, Model Manager, Settings, User Persona, and Worlds. The AI Character Creator opens in its own window.

---

## Voice Shortcuts

No push-to-talk or voice-call hotkeys (Spacebar, etc.) are implemented. Voice features are controlled via the microphone icon in the chat input area (`SttService` + `record` package).

| Shortcut | Action |
|----------|--------|
| (none)   | Click the 🎤 mic icon to start/stop push-to-talk recording |
| (none)   | Use the Voice Call overlay (continuous mode) for hands-free conversation |

See Settings → Voice for STT engine configuration, silence threshold, and auto-send transcription.

---

## Editor Shortcuts

All character, story, and world editors use standard Flutter `TextField` / `TextFormField` widgets. No custom `Actions`/`Intent` or `SingleActivator` keyboard bindings are registered.

| Shortcut                        | Action |
|---------------------------------|--------|
| `Ctrl / ⌘ + C`                  | Copy selected text |
| `Ctrl / ⌘ + V`                  | Paste |
| `Ctrl / ⌘ + X`                  | Cut |
| `Ctrl / ⌘ + Z`                  | Undo |
| `Ctrl / ⌘ + Shift + Z`          | Redo |
| `Ctrl / ⌘ + A`                  | Select all |
| Arrow keys / Home / End / PgUp / PgDn | Standard text navigation and selection |
| `Enter`                         | Submit form (in character creator review step, etc.) |

Rich text formatting shortcuts (bold/italic) are not implemented; the editors are plain-text or Markdown-based.

---

## Platform Notes

- **macOS**: Use the `⌘ Command` key in place of `Ctrl` for all standard OS-level shortcuts (copy, paste, undo, select all, close window, etc.). The chat `Enter` / `Shift+Enter` handler works identically.
- **Windows / Linux**: Use the `Ctrl` key for the same operations.
- The app does not register system-wide global hotkeys (no `hotkey_manager` or similar). All shortcuts require the app window to be focused.
- On all platforms, `Esc` closes most dialogs (standard Material behavior).

For the most up-to-date behavior, the source of truth is the `onKeyEvent` handler on the chat `FocusNode` and Flutter's built-in text editing actions.

