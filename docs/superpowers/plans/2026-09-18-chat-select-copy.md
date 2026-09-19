# Chat select + copy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship drag-select + Copy on visible chat-bubble body (desktop + `web_ui`), remove the lying macOS Edit → Find menu, and stop the transcript from auto-scrolling on new messages or streaming tokens.

**Architecture:** Lift Flutter `SelectionArea` to the bubble-body (speech + expanded thought/raw + banner sentence); strip nested per-segment wraps in `StyledChatMessage`; keep chrome outside the selection subtree. Web keeps native DOM select/copy and adds `user-select` rules. Extract today’s auto-scroll call sites into tiny helpers, prove they jump, then make them no-ops and delete the send/stream pins. No Find bar, no Cmd+F handler, no indexer.

**Tech Stack:** Flutter desktop + web_ui React/TS

## Global Constraints

- 500-line CI ratchet (handwritten lib/ ≥500 fails; database.g.dart excluded)
- DRY, tall Dart, limited comments, analyzer-clean, no dart format .
- Desktop + web_ui same PR
- No legal names in public text
- Path-complete N/A for pure UI presentation (but gesture twins 1:1/group)
- Guard: new tests OK; editing existing tests needs approved-test-change
- **Transcript scroll = B (locked).** CoS candidates were: **A** stick-to-bottom only when already near bottom (if scrolled up, never yank, including streaming); **B** never auto-scroll for new messages/tokens; **C** keep stick-to-bottom but freeze auto-scroll while drag-selecting. The user chose **B**. Never auto-scroll the transcript for new messages or streaming tokens. User scrolls themselves. Desktop + web_ui parity. Journal `jumpToMessage` stays (user tapped). Opening a chat may still start at the newest (initial layout). Do not implement A or C.
- Find is deferred (in-app and OS). Do not add a Find bar, indexer, highlights, or Cmd/Ctrl+F intercept.
- Spec lock: `docs/superpowers/specs/2026-09-18-chat-select-find-design.md` (amended 2026-09-19). Why Find is out: `docs/superpowers/specs/2026-09-18-chat-os-find-investigation.md`.

---

## File map

| Path | Action | Responsibility |
|---|---|---|
| `lib/ui/chat_components/bubbles/selectable_bubble_body.dart` | Create | Thin `SelectionArea` wrapper + `Unselectable` (`SelectionContainer.disabled`) |
| `lib/ui/chat_components/bubbles/styled_chat_message.dart` | Modify | Remove per-segment `SelectionArea` (return `Text` / `RichText` only) |
| `lib/ui/chat_components/bubbles/message_bubble.content.dart` | Modify | Wrap speech + expanded thought + thought-only hint in `SelectableBubbleBody`; leave chip / timer / chips / images out |
| `lib/ui/chat_components/bubbles/message_bubble.dialogs.dart` | Modify | Banner sentence selectable; long-press delete stays |
| `lib/ui/chat_components/bubbles/message_bubble.dart` | Modify only if needed | Do **not** wrap the whole `Column` / `ListView`. Keep header + action rows outside selection. Border painter stays `IgnorePointer`. File is 324 lines — do not grow toward 500. |
| `lib/ui/chat_components/chat_components.dart` | Modify | Export `selectable_bubble_body.dart` |
| `lib/ui/chat_components/stage/transcript_auto_scroll.dart` | Create | Pure policy: `applyTranscriptAutoScroll` — after Task 4, a no-op |
| `lib/ui/pages/chat_page.dart` | Modify | Delete `_autoScroll` and `_scrollToBottom` once the helper is wired/removed. 480 lines — shrink, do not grow. |
| `lib/ui/pages/chat_page.input.dart` | Modify | Remove the post-send `addPostFrameCallback((_) => _scrollToBottom())` |
| `macos/Runner/Base.lproj/MainMenu.xib` | Modify | Delete the entire Edit → Find submenu (keep Copy / Select All / View → Enter Full Screen) |
| `web_ui/src/pages/chat/transcriptAutoScroll.ts` | Create | Pure policy twin of the Dart helper |
| `web_ui/src/pages/chat/useChatSession.ts` | Modify | Remove the `scrollTo({ top: scrollHeight })` effect on `messages.length` / `streaming` |
| `web_ui/src/styles/insight.css` | Modify | `user-select` on `.bubble` / `.thinking-body`; `none` on `.msg-speaker` |
| `web_ui/src/styles/messages.css` | Modify | `user-select: none` on `.msg-actions` / `.swipe` |
| `web_ui/src/styles/living-time.css` | Modify | `user-select: text` on `.dream-banner` |
| `docs/keyboard-shortcuts.md` | Modify | Bubbles selectable; no Find shortcut; macOS Find menu removed |
| `docs/Rawhide.md` | Modify | One user-facing bullet |
| `test/hygiene/macos_find_menu_test.dart` | Create | XIB no longer advertises Find |
| `test/ui/chat_components/selectable_bubble_body_test.dart` | Create | SelectionArea lift + thought/swipe hit-tests |
| `test/ui/chat_components/selectable_banner_test.dart` | Create | Banner select + long-press delete |
| `test/ui/chat_components/transcript_auto_scroll_test.dart` | Create | Viewport stays put after apply |
| `web_ui/src/pages/chat/transcriptAutoScroll.test.ts` | Create | Web scroll policy + source pin |
| `web_ui/src/styles/chatSelect.test.ts` | Create | CSS contract |

Do **not** touch: `chat_service.dart`, `log_view.dart`, existing tests (including `thought_toggle_chat_live_test.dart`, `reading_size_test.dart`, `chatAsideMount.test.tsx`).

---

### Task 1: Disable the lying macOS Find menu

**Files:**
- Test: `test/hygiene/macos_find_menu_test.dart`
- Modify: `macos/Runner/Base.lproj/MainMenu.xib` (Edit menu, the `Find` `menuItem` at id `4EN-yA-p0u` through its closing `</menuItem>`)

**Interfaces:**
- Consumes: nothing
- Produces: XIB with no Find submenu and no `performFindPanelAction:` / `performTextFinderAction:`

- [x] **Step 1: Write the failing test**

```dart
// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final xib = File('macos/Runner/Base.lproj/MainMenu.xib');

  test('macOS Edit menu does not advertise Find', () {
    expect(xib.existsSync(), isTrue);
    final text = xib.readAsStringSync();
    expect(text.contains('performFindPanelAction:'), isFalse);
    expect(text.contains('performTextFinderAction:'), isFalse);
    expect(text.contains('title="Find"'), isFalse);
    expect(text.contains('title="Find…"'), isFalse);
    expect(text.contains('title="Find and Replace…"'), isFalse);
    expect(text.contains('title="Find Next"'), isFalse);
    expect(text.contains('title="Find Previous"'), isFalse);
    expect(text.contains('title="Use Selection for Find"'), isFalse);
    expect(
      text.contains('title="Enter Full Screen"'),
      isTrue,
      reason: '⌃⌘F full screen is not Find — keep it',
    );
  });
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `flutter test test/hygiene/macos_find_menu_test.dart`

Expected: FAIL — `performFindPanelAction:` is still in the XIB (and `title="Find"`).

- [x] **Step 3: Write minimal implementation**

In `macos/Runner/Base.lproj/MainMenu.xib`, delete the separator + Find `menuItem` block that today sits between Select All and Spelling (the block that starts at `<menuItem isSeparatorItem="YES" id="uyl-h8-XO2"/>` and ends at the `</menuItem>` that closes `id="4EN-yA-p0u"`). Leave Select All and Spelling and Grammar adjacent. Do not touch View → Enter Full Screen (`id="4J7-dP-txa"`, `keyEquivalent="f"` with Control).

- [x] **Step 4: Run test to verify it passes**

Run: `flutter test test/hygiene/macos_find_menu_test.dart`

Expected: PASS

- [x] **Step 5: Commit**

```bash
git add test/hygiene/macos_find_menu_test.dart macos/Runner/Base.lproj/MainMenu.xib
git commit -m "fix(macos): remove dead Edit → Find menu that no-ops on Flutter"
```

---

### Task 2: Desktop SelectionArea lift (speech + expanded thought)

**Files:**
- Create: `lib/ui/chat_components/bubbles/selectable_bubble_body.dart`
- Modify: `lib/ui/chat_components/bubbles/styled_chat_message.dart` (`_buildStyledText`, the two `return SelectionArea(...)` tails)
- Modify: `lib/ui/chat_components/bubbles/message_bubble.content.dart` (`_thoughtAndBodyChildren`)
- Modify: `lib/ui/chat_components/chat_components.dart` (add export)
- Test: `test/ui/chat_components/selectable_bubble_body_test.dart`

**Interfaces:**
- Consumes: existing `MessageBubble`, `StyledChatMessage`, `FakeChatService`
- Produces:
  - `class SelectableBubbleBody extends StatelessWidget { const SelectableBubbleBody({super.key, required this.child}); final Widget child; }`
  - `class Unselectable extends StatelessWidget { const Unselectable({super.key, required this.child}); final Widget child; }` — wraps `SelectionContainer.disabled`

- [x] **Step 1: Write the failing tests**

```dart
// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';

ChatMessage _thoughtAndSpeech() {
  return ChatMessage(
    text: '<think>secret plan</think>\nspoken line here',
    sender: 'Iris',
    isUser: false,
  )..thinkingDurationMs = 1200;
}

Widget _withProviders({required Widget child, ChatService? chat}) {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService();
  addTearDown(storage.dispose);
  final tts = FakeTtsService();
  addTearDown(tts.dispose);
  final resolved = chat ?? FakeChatService();
  if (chat == null) addTearDown(resolved.dispose);
  return MaterialApp(
    home: Scaffold(
      body: MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<TtsService>.value(value: tts),
          ChangeNotifierProvider<ChatService>.value(value: resolved),
          ChangeNotifierProvider<UserPersonaService>.value(
            value: FakeUserPersonaService(),
          ),
        ],
        child: SizedBox(width: 680, child: child),
      ),
    ),
  );
}

void main() {
  setupPathProviderMock();

  testWidgets('StyledChatMessage does not own a SelectionArea', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    addTearDown(storage.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: const MaterialApp(
          home: Scaffold(
            body: StyledChatMessage(text: 'hello speech', isUser: false),
          ),
        ),
      ),
    );
    expect(find.byType(SelectionArea), findsNothing);
    expect(find.text('hello speech'), findsOneWidget);
  });

  testWidgets('expanded thought and speech share one body SelectionArea', (
    tester,
  ) async {
    final chat = FakeChatService();
    addTearDown(chat.dispose);
    await tester.pumpWidget(
      _withProviders(
        chat: chat,
        child: MessageBubble(
          message: _thoughtAndSpeech(),
          index: 0,
          chatService: chat,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('thought-toggle')));
    await tester.pump();
    expect(find.text('secret plan'), findsOneWidget);
    expect(find.text('spoken line here'), findsOneWidget);
    final area = tester.element(find.text('spoken line here'));
    expect(
      area.findAncestorWidgetOfExactType<SelectionArea>(),
      isNotNull,
    );
    final thought = tester.element(find.text('secret plan'));
    expect(
      thought.findAncestorWidgetOfExactType<SelectionArea>(),
      isNotNull,
    );
  });

  testWidgets('thought chip still toggles under a selectable body', (
    tester,
  ) async {
    final chat = FakeChatService();
    addTearDown(chat.dispose);
    await tester.pumpWidget(
      _withProviders(
        chat: chat,
        child: MessageBubble(
          message: _thoughtAndSpeech(),
          index: 0,
          chatService: chat,
        ),
      ),
    );
    expect(find.text('secret plan'), findsNothing);
    await tester.tap(find.byKey(const Key('thought-toggle')));
    await tester.pump();
    expect(find.text('secret plan'), findsOneWidget);
  });
}
```

- [x] **Step 2: Run tests to verify they fail**

Run: `flutter test test/ui/chat_components/selectable_bubble_body_test.dart`

Expected: FAIL — `StyledChatMessage does not own a SelectionArea` finds a `SelectionArea` (today’s per-segment wrap). The shared-body test may fail because expanded thought is plain `Text` with no `SelectionArea` ancestor.

- [x] **Step 3: Write minimal implementation**

`lib/ui/chat_components/bubbles/selectable_bubble_body.dart`:

```dart
// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

/// In-scope bubble body (speech + visible thought/raw). One area per bubble.
class SelectableBubbleBody extends StatelessWidget {
  const SelectableBubbleBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SelectionArea(child: child);
}

/// Header, thought chip, swipe/action rows, chips — not bubble content.
class Unselectable extends StatelessWidget {
  const Unselectable({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SelectionContainer.disabled(child: child);
  }
}
```

In `styled_chat_message.dart` `_buildStyledText`, replace both tails so they do **not** wrap `SelectionArea`:

```dart
    if (spans.isEmpty) {
      return Text(segment, style: _rootStyle, textScaler: readingScaler);
    }

    return RichText(
      text: TextSpan(style: _rootStyle, children: spans),
      textScaler: readingScaler,
    );
```

In `message_bubble.content.dart`, collect the in-scope body (expanded thought container, thought-only hint, fallback `Text`, `StyledChatMessage`) into a list and return them as **one** `SelectableBubbleBody` child (`Column` if more than one). Keep the thought **chip** `GestureDetector` (`Key('thought-toggle')`), `LiveThinkingTimer`, `InlineChatImage`, and realism indicator **outside** that wrap. Wrap the chip in `Unselectable` if a parent `SelectionArea` would otherwise include it.

Export from `chat_components.dart`:

```dart
export 'bubbles/selectable_bubble_body.dart';
```

`message_bubble.content.dart` is a `part of` — no import. It can reference `SelectableBubbleBody` once the library (`message_bubble.dart`) sees it via the barrel already imported there (`styled_chat_message.dart` is a direct import; add `import 'selectable_bubble_body.dart';` next to the other bubble imports in `message_bubble.dart` if the barrel is not imported by that library).

- [x] **Step 4: Run tests to verify they pass**

Run: `flutter test test/ui/chat_components/selectable_bubble_body_test.dart test/ui/chat_components/thought_toggle_chat_live_test.dart test/ui/chat_components/reading_size_test.dart`

Expected: PASS (do not edit the last two files if they fail — fix the wrap instead).

- [x] **Step 5: Format only the Dart files you edited, then commit**

```bash
dart format lib/ui/chat_components/bubbles/selectable_bubble_body.dart lib/ui/chat_components/bubbles/styled_chat_message.dart lib/ui/chat_components/bubbles/message_bubble.content.dart lib/ui/chat_components/bubbles/message_bubble.dart lib/ui/chat_components/chat_components.dart test/ui/chat_components/selectable_bubble_body_test.dart
flutter analyze --no-fatal-warnings --no-fatal-infos lib/ui/chat_components/bubbles/selectable_bubble_body.dart lib/ui/chat_components/bubbles/styled_chat_message.dart lib/ui/chat_components/bubbles/message_bubble.content.dart lib/ui/chat_components/bubbles/message_bubble.dart
git add lib/ui/chat_components/bubbles/selectable_bubble_body.dart lib/ui/chat_components/bubbles/styled_chat_message.dart lib/ui/chat_components/bubbles/message_bubble.content.dart lib/ui/chat_components/bubbles/message_bubble.dart lib/ui/chat_components/chat_components.dart test/ui/chat_components/selectable_bubble_body_test.dart
git commit -m "feat(chat): select speech and expanded thought in one bubble area"
```

---

### Task 3: Banner select + long-press delete

**Files:**
- Modify: `lib/ui/chat_components/bubbles/message_bubble.dialogs.dart` (`_narrationBanner`)
- Test: `test/ui/chat_components/selectable_banner_test.dart`

**Interfaces:**
- Consumes: `SelectableBubbleBody` from Task 2
- Produces: banner sentence inside `SelectionArea`; `onLongPress` still opens `Delete Message`

- [x] **Step 1: Write the failing test**

```dart
// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';

void main() {
  setupPathProviderMock();

  Future<void> pumpBanner(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    addTearDown(storage.dispose);
    final chat = FakeChatService();
    addTearDown(chat.dispose);
    final tts = FakeTtsService();
    addTearDown(tts.dispose);
    final msg = ChatMessage(
      text: '[🎰 CHANCE TIME! A raccoon steals the pie]',
      sender: 'System',
      isUser: false,
      metadata: const {'is_chance_time_narration': true},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MultiProvider(
            providers: [
              ChangeNotifierProvider<StorageService>.value(value: storage),
              ChangeNotifierProvider<TtsService>.value(value: tts),
              ChangeNotifierProvider<ChatService>.value(value: chat),
              ChangeNotifierProvider<UserPersonaService>.value(
                value: FakeUserPersonaService(),
              ),
            ],
            child: MessageBubble(message: msg, index: 0, chatService: chat),
          ),
        ),
      ),
    );
  }

  testWidgets('banner sentence is selectable', (tester) async {
    await pumpBanner(tester);
    expect(find.textContaining('A raccoon steals the pie'), findsOneWidget);
    final el = tester.element(find.textContaining('A raccoon steals the pie'));
    expect(el.findAncestorWidgetOfExactType<SelectionArea>(), isNotNull);
  });

  testWidgets('banner long-press still offers delete', (tester) async {
    await pumpBanner(tester);
    await tester.longPress(find.textContaining('A raccoon steals the pie'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Message'), findsOneWidget);
  });
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/chat_components/selectable_banner_test.dart`

Expected: FAIL — banner sentence has no `SelectionArea` ancestor. Long-press delete should already pass; if both fail, fix delete first (do not drop `onLongPress`).

- [x] **Step 3: Write minimal implementation**

In `_narrationBanner`, wrap only the banner **sentence** `Text` (the `Flexible` child) in `SelectableBubbleBody`. Keep the outer `GestureDetector(onLongPress: ...)` on the banner. Do not wrap the emoji-only `Text`. If drag-select fires delete, move `onLongPress` to a non-text chrome hit target or use a hold that is not a drag — the long-press test must stay green.

- [x] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/chat_components/selectable_banner_test.dart`

Expected: PASS (both tests)

- [x] **Step 5: Commit**

```bash
dart format lib/ui/chat_components/bubbles/message_bubble.dialogs.dart test/ui/chat_components/selectable_banner_test.dart
git add lib/ui/chat_components/bubbles/message_bubble.dialogs.dart test/ui/chat_components/selectable_banner_test.dart
git commit -m "feat(chat): make Chance Time and Dream banner text selectable"
```

---

### Task 4: Never auto-scroll on new messages or tokens (option B)

CoS listed A / B / C. This task is **B only** — not a placeholder. Do not add a near-bottom threshold (A) or a “selecting” freeze flag (C).

**Files:**
- Create: `lib/ui/chat_components/stage/transcript_auto_scroll.dart`
- Create: `web_ui/src/pages/chat/transcriptAutoScroll.ts`
- Modify: `lib/ui/pages/chat_page.dart` (delete `_autoScroll`, `_scrollToBottom`)
- Modify: `lib/ui/pages/chat_page.input.dart` (delete the post-send `_scrollToBottom` callback)
- Modify: `web_ui/src/pages/chat/useChatSession.ts` (delete the `scrollTo` effect on `[state?.messages.length, streaming]`)
- Modify: `lib/ui/chat_components/chat_components.dart` (export the Dart helper)
- Test: `test/ui/chat_components/transcript_auto_scroll_test.dart`
- Test: `web_ui/src/pages/chat/transcriptAutoScroll.test.ts`

**Interfaces:**
- Consumes: today’s desktop `_scrollToBottom` (`jumpTo(0)` / `animateTo(0)`) and web `scrollTo({ top: scrollHeight })`
- Produces:
  - Dart: `void applyTranscriptAutoScroll(ScrollController controller, {required bool generating})`
  - TS: `export function applyTranscriptAutoScroll(el: { scrollTop: number; scrollHeight: number; scrollTo?: (init: ScrollToOptions) => void } | null): void`
  - After this task both functions are **no-ops**. Call sites that used to pin the viewport are gone.

- [x] **Step 1: Write the failing tests**

`test/ui/chat_components/transcript_auto_scroll_test.dart`:

```dart
// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/chat_components/stage/transcript_auto_scroll.dart';

void main() {
  testWidgets('applyTranscriptAutoScroll leaves a user-owned offset alone', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          reverse: true,
          itemCount: 40,
          itemBuilder: (_, i) => SizedBox(height: 80, child: Text('row $i')),
        ),
      ),
    );
    controller.jumpTo(240);
    await tester.pump();
    expect(controller.offset, 240);

    applyTranscriptAutoScroll(controller, generating: true);
    applyTranscriptAutoScroll(controller, generating: false);
    await tester.pump();
    expect(
      controller.offset,
      240,
      reason: 'option B: send/stream must not jumpTo(0)',
    );
  });

  test('send and ChatPage no longer pin the transcript', () {
    final input = File('lib/ui/pages/chat_page.input.dart').readAsStringSync();
    expect(input.contains('_scrollToBottom'), isFalse);
    final page = File('lib/ui/pages/chat_page.dart').readAsStringSync();
    expect(page.contains('void _scrollToBottom'), isFalse);
    expect(page.contains('bool _autoScroll'), isFalse);
  });
}
```

`web_ui/src/pages/chat/transcriptAutoScroll.test.ts`:

```ts
import { readFileSync } from 'node:fs';
import { describe, expect, it, vi } from 'vitest';
import { applyTranscriptAutoScroll } from './transcriptAutoScroll';

describe('transcript auto-scroll (option B)', () => {
  it('does not move a user-owned scrollTop on stream or new message', () => {
    const scrollTo = vi.fn();
    const el = { scrollTop: 80, scrollHeight: 400, scrollTo };
    applyTranscriptAutoScroll(el);
    expect(scrollTo).not.toHaveBeenCalled();
    expect(el.scrollTop).toBe(80);
  });

  it('useChatSession does not pin the transcript on messages.length or streaming', () => {
    const src = readFileSync(
      new URL('./useChatSession.ts', import.meta.url),
      'utf8',
    );
    expect(src).not.toMatch(/scrollTo\(\s*\{\s*top:\s*scrollRef/);
    expect(src).not.toMatch(/scrollHeight\s*\}\s*\)/);
  });
});
```

- [x] **Step 2: Run tests to verify they fail**

Run:

```bash
# First add a temporary extract of TODAY's behavior so the widget test is about
# the policy, not a missing import. Create transcript_auto_scroll.dart with the
# old jump (see Step 3 "red body"), export it, then:
flutter test test/ui/chat_components/transcript_auto_scroll_test.dart
```

Expected: FAIL — `applyTranscriptAutoScroll(..., generating: true)` does `jumpTo(0)`, so offset is `0` not `240`. The source-pin half also fails while `_scrollToBottom` still exists.

For web, create `transcriptAutoScroll.ts` with today’s `el?.scrollTo({ top: el.scrollHeight })` first, then:

Run: `cd web_ui && npm test -- src/pages/chat/transcriptAutoScroll.test.ts`

Expected: FAIL — `scrollTo` was called and/or `useChatSession.ts` still has the effect.

**Red body (desktop, temporary — only so Step 2 fails on behavior):**

```dart
// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

void applyTranscriptAutoScroll(
  ScrollController controller, {
  required bool generating,
}) {
  if (!controller.hasClients) return;
  if (generating) {
    controller.jumpTo(0);
  } else {
    controller.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }
}
```

**Red body (web, temporary):**

```ts
export function applyTranscriptAutoScroll(
  el: { scrollTop: number; scrollHeight: number; scrollTo?: (init: ScrollToOptions) => void } | null,
): void {
  if (!el) return;
  el.scrollTo?.({ top: el.scrollHeight });
}
```

- [x] **Step 3: Write minimal implementation (green)**

Replace both helpers with no-ops:

```dart
void applyTranscriptAutoScroll(
  ScrollController controller, {
  required bool generating,
}) {
  // Option B: the user scrolls. [generating] is unused on purpose.
}
```

```ts
export function applyTranscriptAutoScroll(
  _el: { scrollTop: number; scrollHeight: number; scrollTo?: (init: ScrollToOptions) => void } | null,
): void {
  // Option B: the user scrolls.
}
```

In `chat_page.input.dart`, delete:

```dart
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
```

In `chat_page.dart`, delete `bool _autoScroll = true;` and the entire `void _scrollToBottom() { ... }` method.

In `useChatSession.ts`, delete this effect (do not call the helper on every token either):

```ts
  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight });
  }, [state?.messages.length, streaming]);
```

Leave `scrollRef` on the message list (user scroll still needs the node). Leave `jumpToMessage` / Journal jump untouched.

Do **not** edit `web_ui/src/pages/chatAsideMount.test.tsx` (it stubs `Element.scrollTo` — harmless leftover; changing it needs `approved-test-change`).

- [x] **Step 4: Run tests to verify they pass**

Run:

```bash
flutter test test/ui/chat_components/transcript_auto_scroll_test.dart
cd web_ui && npm test -- src/pages/chat/transcriptAutoScroll.test.ts
```

Expected: PASS — offset stays `240`; `scrollTo` not called; source pins clean.

- [x] **Step 5: Commit**

```bash
dart format lib/ui/chat_components/stage/transcript_auto_scroll.dart lib/ui/pages/chat_page.dart lib/ui/pages/chat_page.input.dart lib/ui/chat_components/chat_components.dart test/ui/chat_components/transcript_auto_scroll_test.dart
git add lib/ui/chat_components/stage/transcript_auto_scroll.dart lib/ui/pages/chat_page.dart lib/ui/pages/chat_page.input.dart lib/ui/chat_components/chat_components.dart test/ui/chat_components/transcript_auto_scroll_test.dart web_ui/src/pages/chat/transcriptAutoScroll.ts web_ui/src/pages/chat/transcriptAutoScroll.test.ts web_ui/src/pages/chat/useChatSession.ts
git commit -m "fix(chat): never auto-scroll the transcript on send or stream"
```

---

### Task 5: Web user-select parity

**Files:**
- Modify: `web_ui/src/styles/insight.css`
- Modify: `web_ui/src/styles/messages.css`
- Modify: `web_ui/src/styles/living-time.css`
- Test: `web_ui/src/styles/chatSelect.test.ts`

**Interfaces:**
- Consumes: existing class names `.bubble`, `.thinking-body`, `.dream-banner`, `.msg-speaker`, `.msg-actions`, `.swipe`
- Produces: CSS rules only — no Find intercept, no `preventDefault` on Cmd+F

- [x] **Step 1: Write the failing test**

```ts
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

function read(rel: string): string {
  return readFileSync(new URL(rel, import.meta.url), 'utf8');
}

describe('chat select/copy CSS', () => {
  it('marks bubble body and thought as selectable', () => {
    const insight = read('./insight.css');
    expect(insight).toMatch(/\.bubble\s*\{[^}]*user-select:\s*text/);
    expect(insight).toMatch(/\.thinking-body\s*\{[^}]*user-select:\s*text/);
    expect(insight).toMatch(/\.msg-speaker\s*\{[^}]*user-select:\s*none/);
  });

  it('keeps action chrome unselectable', () => {
    const messages = read('./messages.css');
    expect(messages).toMatch(/\.msg-actions\s*\{[^}]*user-select:\s*none/);
    expect(messages).toMatch(/\.swipe\s*\{[^}]*user-select:\s*none/);
  });

  it('marks dream banners selectable', () => {
    const living = read('../living-time.css');
    expect(living).toMatch(/\.dream-banner\s*\{[^}]*user-select:\s*text/);
  });
});
```

Place the test at `web_ui/src/styles/chatSelect.test.ts` so `./insight.css` resolves.

- [x] **Step 2: Run test to verify it fails**

Run: `cd web_ui && npm test -- src/styles/chatSelect.test.ts`

Expected: FAIL — those `user-select` declarations are not in the files yet.

- [x] **Step 3: Write minimal implementation**

Add **inside** the existing rule blocks (do not duplicate selectors if you can append to the current `{ ... }`).

`insight.css` — in `.bubble { ... }` add `user-select: text; -webkit-user-select: text;`

Add a new rule (thinking-body lives in `places.css` today; **also** set it in `insight.css` so the chat transcript does not depend on Places):

```css
.thinking-body { user-select: text; -webkit-user-select: text; }
.msg-speaker { user-select: none; -webkit-user-select: none; }
```

`messages.css` — append to `.msg-actions` and `.swipe`:

```css
user-select: none; -webkit-user-select: none;
```

`living-time.css` — append to `.dream-banner`:

```css
user-select: text; -webkit-user-select: text;
```

Do **not** add a Cmd+F listener. Do **not** set `user-select: none` on `.chat-messages`.

- [x] **Step 4: Run test to verify it passes**

Run: `cd web_ui && npm test -- src/styles/chatSelect.test.ts`

Expected: PASS

- [x] **Step 5: Commit**

```bash
git add web_ui/src/styles/insight.css web_ui/src/styles/messages.css web_ui/src/styles/living-time.css web_ui/src/styles/chatSelect.test.ts
git commit -m "feat(web): user-select on bubble body, not speaker or actions"
```

After this task: `cd web_ui && npm run build` (required whenever `web_ui/` changes — writes `assets/web_app`).

---

### Task 6: Keyboard shortcuts, Rawhide, poke checklist

**Files:**
- Modify: `docs/keyboard-shortcuts.md`
- Modify: `docs/Rawhide.md`

**Interfaces:**
- Consumes: shipped behavior from Tasks 1–5
- Produces: user-facing notes only (no Find shortcut)

- [x] **Step 1: Edit keyboard-shortcuts.md**

In **Standard Text Editing**, after the table, add a short paragraph:

```markdown
Chat bubbles are the same: drag across the spoken line (and an expanded Thought) and use **Copy** or `Ctrl / ⌘ + C`. The name and buttons on the bubble are not part of that selection.

macOS **Edit → Find** (`⌘F`) is not in the menu. It used to be a leftover from the app template and did nothing on the chat canvas. The browser UI may still open the browser’s own Find — that is the browser, not Front Porch.
```

Do **not** add a Find-in-chat shortcut row.

- [x] **Step 2: Edit Rawhide.md**

Under **Recent improvements**, add one bullet at the top of the unreleased list:

```markdown
- 📋 **Copy a reply like any other text** — drag across the words in a bubble (including an open Thought) and Copy. The character name and the buttons stay out of it. Sending a new line no longer yanks the transcript if you had scrolled up. Same on the phone. macOS Edit → Find is gone; it never searched the chat.
```

- [x] **Step 3: Commit**

```bash
git add docs/keyboard-shortcuts.md docs/Rawhide.md
git commit -m "docs: chat select/copy shortcuts and Rawhide note"
```

- [ ] **Step 4: Maintainer poke (implementation PR — not this docs PR)**

1. 1:1 chat, long reply: drag a sentence → right-click Copy → paste in the composer. Header name must not be on the clipboard.
2. Expand Thought; drag thought + speech; Copy. Collapse Thought — that text is gone.
3. Group: tap speaker name (still queues). Swipe chevrons still work. Select the new body. Mac: Edit has no Find.
4. Scroll up, send (or stream). Viewport stays put. Same on the PWA. Browser ⌘F may still open the browser bar.

---

## Exact commands (implementation PR)

```bash
flutter test test/hygiene/macos_find_menu_test.dart
flutter test test/ui/chat_components/selectable_bubble_body_test.dart
flutter test test/ui/chat_components/selectable_banner_test.dart
flutter test test/ui/chat_components/transcript_auto_scroll_test.dart
flutter test test/ui/chat_components/thought_toggle_chat_live_test.dart
flutter test test/ui/chat_components/reading_size_test.dart
flutter analyze --no-fatal-warnings --no-fatal-infos
cd web_ui && npm test -- src/pages/chat/transcriptAutoScroll.test.ts src/styles/chatSelect.test.ts
cd web_ui && npm run lint && npm test
cd web_ui && npm run build
```

Never `dart format .`. Never edit `pubspec.yaml`.

---

## Self-review — spec coverage

| Spec lock | Task |
|---|---|
| §1.1 Select/copy visible bubble body | Task 2, Task 3 |
| §1.2 Find deferred — no bar / no Cmd+F | No task adds Find; Task 6 docs say so |
| §1.3 Desktop + web same implementation PR | Tasks 2–5 in one later PR |
| §1.4 Start from SelectionArea, fix gestures | Task 2 (lift + chip tap) |
| §1.5 macOS Find menu gone | Task 1 |
| §1.6 / §6.5 Never auto-scroll send/stream (B locked; A/C out) | Task 4 (not a placeholder — letter arrived) |
| §6.1 Remove nested SelectionArea | Task 2 |
| §6.2 Thought / swipe / banner / Cmd+R | Tasks 2–3; Cmd+R untouched |
| §8 Web user-select; no preventDefault F | Task 5 |
| §8 / §6.5 Web scroll effect removed | Task 4 |
| §9 / §11 Docs + poke | Task 6 |
| Journal jump stays | Task 4 explicitly leaves `jumpToMessage` |
| `log_view.dart` untouched | File map |

**Placeholder scan:** no TBD / “implement later” / “write tests for the above.” Scroll Task 4 is **B**, not an A/B/C stub — CoS listed the three candidates; the user locked B.

**Type consistency:** `applyTranscriptAutoScroll` is the name on both Dart and TS. `SelectableBubbleBody` / `Unselectable` are the only new widgets.

**Residual:** Flutter cannot easily widget-test “right-click Copy put bytes on the clipboard” in CI; the poke script covers that. Web `chatAsideMount.test.tsx` still stubs `scrollTo` — leave it.

---

Do **not** implement this plan in the docs PR. Implementation is a later PR on Rawhide that includes desktop + `web_ui` together.
)
