# Chat select + Find

**Date:** 2026-09-18
**Status:** Product lock approved — design only (no implementation in this PR)
**Audience:** implementing agents (the maintainer cannot read Dart)
**Surfaces:** Flutter desktop (Windows / macOS / Linux) and `web_ui` in the **same later implementation PR**

Users cannot highlight a reply and copy it, and they cannot Find a phrase in the open chat. `StyledChatMessage` already wraps speech in `SelectionArea`, but thought/raw, narration banners, and several bubble gestures fight that path. This spec is how we make select/copy and Find feel native without inventing a search product.

---

## 1. Locked product (do not reopen)

1. **Select / copy.** Click-drag select + right-click **Copy**, plus standard Ctrl/Cmd+C. Scope is **everything visible in the chat bubble**: spoken body, plus thought/raw **when those are on screen**. Names and timestamps that sit **outside** the bubble are out. Header chrome that lives *inside* the bubble (sender name, edit/fork/delete, TTS) is **not** treated as bubble content.
2. **Find.** A feels-native **in-app** Find bar. Cmd/Ctrl+F opens it, next/prev, match count, highlight the active match, Esc closes. **Not** the OS Find panel. **Not** a heavy custom search UI.
3. **Parity.** Desktop and `web_ui` ship together in the implementation PR. This document is design-only.
4. **Start from what exists.** Do not invent a new selection system where `SelectionArea` already wraps speech. Fix gesture and context-menu conflicts; widen the selectable region to the rest of the on-screen bubble body.

---

## 2. Goals

- Drag-select any on-screen bubble body (speech, expanded thought/raw, Chance Time / Dream banner text) and copy it with the platform Copy command.
- Open a slim Find bar from the open chat with Cmd/Ctrl+F, jump next/prev, see `N of M`, land on the active match, close with Esc.
- Find only what the user can see in the transcript right now (collapsed thought is invisible → not searchable).
- Leave swipe chevrons, thought toggle, group-name tap-to-queue, edit/fork/delete, and narration-banner long-press delete working. Selection must not steal those hits.
- Same capabilities and the same visual language on desktop and web.

## 3. Non-goals

- OS / browser Find panel (macOS Edit → Find, Chrome/Safari Find, `window.find()`).
- PlatformViews, `HtmlElementView`, or embedding a native text view to get selection “for free.”
- Library-wide or cross-chat search. Find is **this open transcript only**.
- Regex, replace, whole-word, diacritic folding, or a search-history product.
- Selecting or indexing sidebar, composer, realism chips, suggest-action pills, the “Thought” chip label, or button tooltips.
- Cross-bubble drag-select (one highlight spanning two messages).
- Changing generation, Realism, Needs, Journal, or swipe **state**. Find only reads visible text.

---

## 4. What is in the bubble (today)

### Desktop (`MessageBubble`)

The painted bubble `Container` already holds, top to bottom:

| Region | Today | Select / Find |
|---|---|---|
| Header: sender name, TTS, edit, fork, delete | Inside the container | **Out.** Chrome, not body. |
| Thought chip (“Thought”) | `GestureDetector` + label | Chip label **out**. |
| Expanded thinking body | Plain `Text` — **not** in `SelectionArea` | **In, when expanded.** |
| Thought-only hint | Plain `Text` | **In** (it is the visible body). |
| Spoken body | `StyledChatMessage` → per-segment `SelectionArea` around `Text` / `RichText` | **In.** Keep selection; stop splitting it per segment. |
| Inline generated / external images | Widgets | Image pixels **out**. Visible alt/caption text **in**. |
| Realism chips, swipe chevrons, action row | Controls | **Out.** |
| Chance Time / Dream banners | Separate row; body is the banner sentence; long-press deletes | Banner **sentence is in** (it *is* the body). |

Sender name and timestamps that appear **outside** a bubble (web speaker label; any future gutter clock) stay out.

### Web (`ChatMessageList.tsx`)

Thought is currently a `<details class="thinking">` **sibling above** `.bubble`, and the group speaker is `.msg-speaker` outside the bubble. Product scope still includes expanded thought when it is on screen. The implementation PR may wrap thought + `.bubble` in one transcript-body container for highlight/select; it must not start indexing the speaker label just because the wrap is convenient.

There is no separate “raw” pane today. **Raw** in this spec means whatever secondary body the UI is actually painting (expanded reasoning / unsanitized body if a later toggle shows one). Do not invent a raw view here.

---

## 5. User flows

### 5.1 Select + copy

1. Pointer down on bubble **body** text, drag, release. Highlight follows the drag. Buttons and chevrons still receive their own clicks.
2. Right-click on the highlight → platform/Flutter context menu with **Copy**. Ctrl/Cmd+C copies the same plain text.
3. Ctrl/Cmd+A while the selection is in a bubble selects **that bubble’s in-scope body**, not the whole app and not the composer.
4. Expanded thought/raw is the same gesture as speech. Collapsed thought cannot be selected (it is not on screen).
5. Clicking a control (edit, swipe, thought chevron) or clicking empty chat chrome clears the highlight. Starting a new drag replaces it.
6. Copy puts **visible plain text** on the clipboard (the words the user highlighted). No HTML, no image bytes, no hidden think tags.

### 5.2 Find

1. In an open chat, press Cmd/Ctrl+F. A slim Find bar appears on the chat column (not a modal, no dimming). Focus moves to its field; the current query (if any) is selected so the next keystroke replaces it.
2. Typing filters immediately. Count shows `N of M` (or `0 of 0` when nothing matches). All matches get a quiet highlight; the **active** match gets a stronger one.
3. The transcript scrolls so the active match is visible (reuse the existing bubble-key jump; see §7).
4. Next: Enter or Cmd/Ctrl+G. Previous: Shift+Enter or Shift+Cmd/Ctrl+G. Wrap at the ends.
5. Empty query: no highlights, no jump, count idle.
6. Esc closes the bar, clears highlights, and returns focus to the composer (or the previously focused control). If Find is open, Esc **does not** also close the insight/session drawers.
7. Cmd/Ctrl+F while the bar is already open focuses and selects the query. It does not open a second bar.
8. Find stays up across streaming tokens and swipe/Continue text changes; the index refreshes from the new visible text.

---

## 6. Desktop approach

### 6.1 Selection

**Do not replace `SelectionArea`.** Change how it is applied.

Today `_buildStyledText` wraps **each** speech segment in its own `SelectionArea`. A message that splits around a markdown image is a `Column` of independent selection islands. Thought, the thought-only hint, and narration banners are not wrapped at all.

Implementation shape (later PR):

- One `SelectionArea` (or `SelectionContainer.disabled` around chrome) whose **enabled** subtree is the in-scope body: speech + visible thought/raw + banner sentence.
- Lift it to the bubble-body level so a drag can cross speech and an expanded thought in the same bubble. Do **not** wrap the whole `ListView` — that would select names, chips, and neighboring bubbles.
- Wrap header icons, thought-chip hit target, swipe/action rows, and the decorative border `CustomPaint` so they are **not** selectable. The border painter must stay `IgnorePointer` (theme-preset tap-swallow bug).
- Use `contextMenuBuilder` only to keep the **standard** Copy (and Select all) items. No custom “Search in chat” product menu.
- Ctrl/Cmd+C is Flutter’s existing selection Copy. Do not add a parallel clipboard path.

### 6.2 Gesture / context-menu conflicts (the actual work)

Flutter’s selection gestures share the arena with parent `GestureDetector`s. Known collisions:

| Existing gesture | Risk | Rule |
|---|---|---|
| Thought chip `onTap` | Parent opaque detector eats the drag | Detector stays on the **chip row only**, never the expanded thought body. |
| Group sender `onTap` (queue next) | Name is in the header | Header stays outside the selection subtree. Tap still queues. |
| Narration banner `onLongPress` → delete | Desktop drag-select vs long-press | Long-press delete **stays** (banners have no action row). Selection is **click-drag**. A completed drag must not fire delete. If the arena still fights, use a `Listener` / `onSecondaryTap` for the menu and keep long-press at a hold that is clearly not a drag. |
| Swipe / greeting chevrons | `InkWell` under a selection wrap | Chevrons stay **outside** the `SelectionArea`. They are buttons, not a horizontal-drag-on-the-bubble gesture. |
| Composer focus + Enter / Cmd+R | Page-level key handler | Find shortcuts are registered **above** the composer `FocusNode` so Cmd+F is not typed into the box and does not collide with Cmd+R. |
| Right-click | Default `SelectionArea` menu vs any future bubble menu | Body right-click = selection menu (Copy). Icon buttons keep their own tooltips/clicks. |

Mobile/touch is not a ship target for this desktop app, but the same widgets render if someone stretches a window onto a touch screen: do not rely on “long-press starts selection” on banners.

### 6.3 Find overlay ownership

- **Owner:** `ChatPage` (the same `State` that already owns `_bubbleKeys`, `_jumpFlashMessage`, and `_buildPageOverlays`).
- **Not** a `showDialog`. Dialogs dim the transcript and steal the overlay stack from voice-call / realism / ONNX download.
- Slim bar: query field, `N of M`, previous, next, close. Warm-porch chrome (`AppColors.formMasterAccent` / `porchAmberOf`, `onChaosAccent` on filled controls). No results list, no filters row.
- Shortcuts via `CallbackShortcuts` / `Shortcuts` on the **page** (chat route focused), not only the composer:
  - Cmd/Ctrl+F → open / focus Find
  - Esc → close Find if open (composer and existing dialogs keep their own Esc when Find is closed)
  - Enter / Cmd+G / Shift variants as in §5.2, **only while the Find field has focus** so composer Enter still sends
- Virtualized reverse `ListView.builder`: search the **in-memory visible-text index**, then `jumpToMessage` + page-owned `GlobalKey`s. Do **not** mint `GlobalObjectKey(message)` (duplicate-key crash when two chat routes are alive).
- Active-match flash may reuse `_jumpFlashMessage` / `JumpFlash`. Distinct from a Journal receipt jump only in color if both can coincide; they must not share a key.

Waifu Coder reuses `ChatMessageList` / `MessageBubble`. If that page is a chat transcript with the same bubbles, it gets the same select rules. Find on Waifu is **not** required in the first implementation PR unless it is cheap because the overlay is already a shared widget.

---

## 7. What Find indexes

Build a list of `{message, field, text, start, end}` from the **open session’s messages**, using only text the UI would paint **right now**:

| Source | Indexed? |
|---|---|
| `displayText` / spoken body (including streaming tail) | Yes |
| Expanded `thinkingContent` | Yes |
| Thought-only hint string | Yes, if that hint is showing |
| Chance Time / Dream banner sentence | Yes (the cleaned sentence the banner shows, not unused wrapper tags) |
| Collapsed thought | **No** |
| Sender / persona name, timestamps, chip labels, button labels | **No** |
| Hidden think tags, sanitizer internals, prompt sections, sidebar | **No** |
| Other chats / other sessions | **No** |

Matching: case-insensitive substring. No regex. First match after the current viewport (or after the caret if a selection exists) becomes active; wrap.

Refresh the index when messages, swipe index, Continue tail, thought-open flags, or streaming text change. Thought-open is **per-bubble UI state**; the index must see those flags, not only `ChatMessage` fields. A word that exists only in a **collapsed** thought is a miss (`0 of 0`) until the user expands that thought and the index refreshes. Find does **not** auto-open thought to create a hit — that would search text that is not on screen.

Scrolling to a match that is not mounted uses the existing `jumpToMessage` hop + viewport paging.

---

## 8. Web approach

Browser selection and Copy already work on ordinary DOM text. Do not replace that with a JS selection library.

- `user-select: text` on spoken body, expanded `.thinking-body`, thought-only hint, and banner text.
- `user-select: none` on `.msg-actions`, swipe chrome, insight chrome, speaker labels. Do not set `user-select: none` on the transcript.
- Right-click Copy is the **browser** menu. Ctrl/Cmd+C is the browser default. No custom clipboard polyfill on secure origins.
- Find is an **in-app** bar that **matches the desktop UX** (placement, count, next/prev, active highlight, Esc). On Cmd/Ctrl+F, `preventDefault()` so the browser Find panel does not open. Same for Cmd/Ctrl+G while our bar is open.
- Esc: if Find is open, close it and stop. Existing ChatPage Esc (close insight / sessions) runs only when Find is closed. Message-edit modal still owns its own Esc.
- Highlights: mark ranges in the visible body (e.g. `<mark>` / a shared highlight class). Active match uses the porch amber highlight; other matches are quieter. Do not use `window.find()`.
- Index the same visible-text rules as §7. Thought in a closed `<details>` is not indexed and Find does not open it to manufacture a hit. Expand it yourself, then search again.
- Scroll the active match into view (`scrollIntoView`). No Flutter `GlobalKey` issues on web; still key rows by message index, not a reused object identity across two mounted chats if that can happen in the PWA.
- Composer: Cmd/Ctrl+F must not insert `f`. Enter in the Find field is next-match, not send.

Phone/PWA: there is no Cmd+F. Select/copy stays native long-press select. A Find **button** is not required; the bar may appear only when a keyboard shortcut fires. If a later PR wants a menu item, it is additive.

---

## 9. Accessibility and keyboard

| Key | Context | Action |
|---|---|---|
| Cmd/Ctrl+F | Chat route focused (composer or transcript) | Open / focus Find |
| Esc | Find open | Close Find, restore prior focus |
| Enter / Cmd+G | Find field focused | Next match |
| Shift+Enter / Shift+Cmd+G | Find field focused | Previous match |
| Cmd/Ctrl+C | Selection in a bubble | Copy |
| Cmd/Ctrl+A | Selection in a bubble | Select that bubble body |
| Cmd/Ctrl+R | Composer (existing) | Regen — **unchanged** |
| Enter | Composer, Find closed | Send — **unchanged** |

- Find field: label “Find in chat”, `role="search"`, count announced (`aria-live="polite"` on web; Flutter `Semantics` on desktop).
- Next/prev/close are real buttons with tooltips (`Next match`, etc.).
- Highlights are not color-only: active match also scrolls into view and the count changes.
- Tab from the Find field cycles its controls, then the composer — it does not trap focus in the transcript.
- Screen readers still see bubble text as text, not as a single non-semantic paint.

Update `docs/keyboard-shortcuts.md` in the **implementation** PR (desktop and the web extras table). Not in this design PR.

---

## 10. Interaction with existing chat gestures (must not steal selection)

Implementation checklist — if any item fails, the PR is incomplete:

1. Drag-select on speech does **not** toggle thought, queue a group speaker, swipe, regen, or delete.
2. Thought chevron still toggles; the expanded thought body is selectable.
3. Swipe and greeting chevrons still change the variant; Find reindexes the new body.
4. Banner long-press still offers delete; a text drag on the banner does not delete.
5. Edit / fork / delete icon hits stay reliable (the `IgnorePointer` border painter stays).
6. Journal receipt jump and Find jump share `jumpToMessage` + page-owned keys; they do not crash when two chat routes are alive.
7. Streaming does not clear an in-progress drag unless the bubble’s text identity is replaced mid-gesture; if that is unavoidable, dropping the highlight is acceptable — do not drop the Find bar.
8. Composer selection/copy is unchanged when Find is closed.

This is presentation/UX. 1:1 vs group must behave the same. Continue vs regen only matter because they change visible text (reindex). No generation-path twins.

---

## 11. Testing and poke script

### Automated (implementation PR)

Prove each new guard red before green.

**Desktop**

- Widget test: drag-select path exists on speech (`SelectionArea` / selectable text at the body, not only a comment).
- Thought collapsed → Find index omits thinking text; expand → it appears.
- Cmd+F (or the bound intent) opens the bar; Esc closes it; next/prev wrap; `0 of 0` on no match.
- Thought-chip tap and swipe chevron still receive taps when a `SelectionArea` ancestor exists (hit-test, not golden-only).
- Banner long-press still invokes delete; a drag does not.
- Jump uses the page-owned key map (reuse / extend `message_key_scope_test` thinking — no `GlobalObjectKey(msg)`).

**Web**

- Vitest: visible-text indexer (collapsed thought excluded; speaker label excluded).
- Keydown: Cmd/Ctrl+F `preventDefault`s; Esc closes Find before drawers.
- Highlight helper marks the active index.

**Not required here:** goldens of the Find bar unless the implementation PR already has a linux-gated chat chrome golden that would otherwise drift.

### Poke script (maintainer, ~15 seconds)

A sandbox cannot self-certify this. After the implementation PR:

1. Open a 1:1 chat with a long reply. Drag across a sentence → right-click Copy → paste into the composer. Confirm you did **not** copy the character name from the header.
2. Expand Thought. Drag across thought + speech in that bubble. Copy. Collapse Thought. Cmd+F a word that exists **only** in that thought — must be `0 of 0`. Expand Thought again — the same query must hit. Then search a spoken word, next/prev, Esc.
3. Group chat: tap a speaker name (still queues next). Swipe a reply with the chevrons. Drag-select the new body. Cmd+F still works. Repeat in the web UI in the same session: browser Copy works; Cmd+F opens **our** bar, not the browser’s.

---

## 12. Out of scope (literal)

- The OS Find panel, browser Find, or any `PlatformView` / native `NSTextView` / Win32 Edit host.
- Implementing the feature in this docs PR.
- Changing `CLAUDE.md` beyond a one-line index pointer (none added; this folder had no index).
- User-facing `docs/Rawhide.md` notes — those land with the implementation PR.

---

## 13. Open questions (short)

Locked decisions are in §1. Only these remain, and the recommended answer is the default if the implementation PR does not get a new maintainer call:

1. **Case-sensitive toggle?** No. Native-feeling bar, not a search product. Case-insensitive only.
2. **Find on Waifu Coder in the first implementation PR?** Only if the overlay is already a shared widget used by `ChatPage`. Otherwise defer; select-in-bubble still applies because the bubble widget is shared.
3. **Cross-bubble select later?** No, unless a later lock says so.

---

## 14. Implementation PR (later — not this change)

One PR, desktop + `web_ui`:

- Bubble-body `SelectionArea` / web `user-select` per §6–§8.
- `ChatPage` + `web_ui` ChatPage Find bar + shortcuts.
- Visible-text indexer + `jumpToMessage` / `scrollIntoView`.
- Keyboard-shortcuts doc + tests + poke script above.

Do not grow `chat_service.dart` or any god file. This is UI state on the chat page.
)
