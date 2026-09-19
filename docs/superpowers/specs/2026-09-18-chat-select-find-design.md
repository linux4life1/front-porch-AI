# Chat select + copy

**Date:** 2026-09-18 (amended 2026-09-19)
**Status:** Product lock approved — **select/copy ships; all Find is deferred**
**Audience:** implementing agents (the maintainer cannot read Dart)
**Surfaces:** Flutter desktop (Windows / macOS / Linux) and `web_ui` in the **same implementation PR**
**Why Find is out:** `docs/superpowers/specs/2026-09-18-chat-os-find-investigation.md` — Flutter `SelectionArea` does not give OS Find; a native transcript would blow up the bubble stack; Windows/Linux have no system Find for a canvas. User decision 2026-09-19: ship select/copy only.

Users cannot highlight a reply and copy it. `StyledChatMessage` already wraps speech in `SelectionArea`, but thought/raw, narration banners, and several bubble gestures fight that path. This spec is how we make **select/copy** work. It is **not** a Find product.

---

## 1. Locked product (do not reopen)

1. **Select / copy (SHIP).** Click-drag select + right-click **Copy**, plus standard Ctrl/Cmd+C. Scope is **everything visible in the chat bubble**: spoken body, plus thought/raw **when those are on screen**. Names and timestamps that sit **outside** the bubble are out. Header chrome that lives *inside* the bubble (sender name, edit/fork/delete, TTS) is **not** treated as bubble content.
2. **Find (DEFERRED).** No in-app Find bar. No OS Find panel. No Cmd/Ctrl+F handler. No indexer, highlights, or jump-to-match. Do not implement any of §5.2 / §6.3 / §7 from the 2026-09-18 draft. See the OS Find investigation for why literal OS Find is a dead end on Flutter desktop.
3. **Parity.** Desktop and `web_ui` ship select/copy together in the implementation PR.
4. **Start from what exists.** Do not invent a new selection system where `SelectionArea` already wraps speech. Fix gesture and context-menu conflicts; widen the selectable region to the rest of the on-screen bubble body.
5. **macOS Find menu (SHIP — must).** The template Edit → Find submenu in `macos/Runner/Base.lproj/MainMenu.xib` advertises Find… (⌘F), Find Next (⌘G), and friends via `performFindPanelAction:`. That is a **lying no-op** on a Flutter canvas. **Disable or remove that entire Find submenu** (and its key equivalents) so the menu bar stops promising Find. Keep Copy / Cut / Paste / Select All. Keep View → Enter Full Screen (⌃⌘F) — that is not Find.
6. **Transcript scroll (SHIP — option B).** CoS listed three candidates; the user picked **B**. **Never auto-scroll the transcript for new messages or streaming tokens.** The user scrolls. Desktop and `web_ui` the same. Journal receipt tap-to-jump stays (the user asked to move). Opening a chat may still **start** at the newest message (initial layout of a reverse list / first paint) — that is not a jump after the user already has a viewport.

   Candidates (not this ship):

   - **A)** Stick-to-bottom only when already near bottom; if scrolled up, never yank (including streaming).
   - **B)** Never auto-scroll for new messages/tokens. **← locked.**
   - **C)** Keep stick-to-bottom but freeze auto-scroll while drag-selecting.

---

## 2. Goals

- Drag-select any on-screen bubble body (speech, expanded thought/raw, Chance Time / Dream banner text) and copy it with the platform Copy command.
- Leave swipe chevrons, thought toggle, group-name tap-to-queue, edit/fork/delete, and narration-banner long-press delete working. Selection must not steal those hits.
- Same select/copy capabilities on desktop and web.
- macOS Edit menu no longer lists Find.
- New replies and streaming tokens do **not** yank the transcript. If you scrolled up to copy, you stay there.

## 3. Non-goals (this ship)

- In-app Find bar, Cmd/Ctrl+F, next/prev, match count, highlight-active-match.
- OS / browser Find panel (macOS Edit → Find, Chrome/Safari Find, `window.find()`). **Web: do not `preventDefault` Cmd/Ctrl+F.** Browser Find may still open; we are not building or stealing it.
- PlatformViews, `HtmlElementView`, or embedding a native text view.
- Library-wide or cross-chat search.
- Selecting sidebar, composer, realism chips, suggest-action pills, the “Thought” chip label, or button tooltips.
- Cross-bubble drag-select (one highlight spanning two messages).
- Changing generation, Realism, Needs, Journal, or swipe **state**.
- A “scroll to latest” button or sticky-bottom follow mode (not requested).
- Changing `log_view.dart` or other non-transcript auto-scroll.

---

## 4. What is in the bubble (today)

### Desktop (`MessageBubble`)

The painted bubble `Container` already holds, top to bottom:

| Region | Today | Select / copy |
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

Thought is currently a `<details class="thinking">` **sibling above** `.bubble`, and the group speaker is `.msg-speaker` outside the bubble. Product scope still includes expanded thought when it is on screen. The implementation PR may wrap thought + `.bubble` in one transcript-body container for select; it must not make the speaker label selectable just because the wrap is convenient.

There is no separate “raw” pane today. **Raw** means whatever secondary body the UI is actually painting (expanded reasoning / unsanitized body if a later toggle shows one). Do not invent a raw view here.

---

## 5. User flows

### 5.1 Select + copy

1. Pointer down on bubble **body** text, drag, release. Highlight follows the drag. Buttons and chevrons still receive their own clicks.
2. Right-click on the highlight → platform/Flutter context menu with **Copy**. Ctrl/Cmd+C copies the same plain text.
3. Ctrl/Cmd+A while the selection is in a bubble selects **that bubble’s in-scope body**, not the whole app and not the composer.
4. Expanded thought/raw is the same gesture as speech. Collapsed thought cannot be selected (it is not on screen).
5. Clicking a control (edit, swipe, thought chevron) or clicking empty chat chrome clears the highlight. Starting a new drag replaces it.
6. Copy puts **visible plain text** on the clipboard (the words the user highlighted). No HTML, no image bytes, no hidden think tags.

### 5.2 Find — deferred

Not in this ship. No bar, no shortcuts, no index. Investigation: `2026-09-18-chat-os-find-investigation.md`.

---

## 6. Desktop approach

### 6.1 Selection

**Do not replace `SelectionArea`.** Change how it is applied.

Today `_buildStyledText` wraps **each** speech segment in its own `SelectionArea`. A message that splits around a markdown image is a `Column` of independent selection islands. Thought, the thought-only hint, and narration banners are not wrapped at all.

Implementation:

- One `SelectionArea` (or `SelectionContainer.disabled` around chrome) whose **enabled** subtree is the in-scope body: speech + visible thought/raw + banner sentence.
- Lift it to the bubble-body level so a drag can cross speech and an expanded thought in the same bubble. Do **not** wrap the whole `ListView` — that would select names, chips, and neighboring bubbles.
- Wrap header icons, thought-chip hit target, swipe/action rows, and the decorative border `CustomPaint` so they are **not** selectable. The border painter must stay `IgnorePointer` (theme-preset tap-swallow bug).
- Use `contextMenuBuilder` only to keep the **standard** Copy (and Select all) items. No “Search in chat” menu item.
- Ctrl/Cmd+C is Flutter’s existing selection Copy. Do not add a parallel clipboard path.
- Remove the inner per-segment `SelectionArea`s from `StyledChatMessage` so they do not nest under the body-level one.

### 6.2 Gesture / context-menu conflicts (the actual work)

Flutter’s selection gestures share the arena with parent `GestureDetector`s. Known collisions:

| Existing gesture | Risk | Rule |
|---|---|---|
| Thought chip `onTap` | Parent opaque detector eats the drag | Detector stays on the **chip row only**, never the expanded thought body. |
| Group sender `onTap` (queue next) | Name is in the header | Header stays outside the selection subtree. Tap still queues. |
| Narration banner `onLongPress` → delete | Desktop drag-select vs long-press | Long-press delete **stays** (banners have no action row). Selection is **click-drag**. A completed drag must not fire delete. If the arena still fights, use a `Listener` / `onSecondaryTap` for the menu and keep long-press at a hold that is clearly not a drag. |
| Swipe / greeting chevrons | `InkWell` under a selection wrap | Chevrons stay **outside** the `SelectionArea`. They are buttons, not a horizontal-drag-on-the-bubble gesture. |
| Composer focus + Enter / Cmd+R | Page-level key handler | **Do not** register Cmd/Ctrl+F. Leave Enter and Cmd+R alone. |
| Right-click | Default `SelectionArea` menu vs any future bubble menu | Body right-click = selection menu (Copy). Icon buttons keep their own tooltips/clicks. |

Mobile/touch is not a ship target for this desktop app, but the same widgets render if someone stretches a window onto a touch screen: do not rely on “long-press starts selection” on banners.

### 6.3 Find overlay — deferred

`ChatPage` does **not** grow a Find bar, shortcuts, or overlay. Do not add Find state next to `_bubbleKeys` / `_jumpFlashMessage`.

Waifu Coder reuses `ChatMessageList` / `MessageBubble`. It gets the same **select** rules because the bubble widget is shared. No Find on Waifu.

### 6.4 macOS menu

Remove (preferred) or disable the entire Edit → Find submenu in `macos/Runner/Base.lproj/MainMenu.xib` so these strings and selectors are gone from the file:

- `performFindPanelAction:` / `performTextFinderAction:`
- Menu titles Find / Find… / Find and Replace… / Find Next / Find Previous / Use Selection for Find
- ⌘F / ⌘G / ⇧⌘G / ⌘E bindings that belonged to that submenu

Do **not** remove View → Enter Full Screen (`keyEquivalent="f"` with the Control modifier). That is a different item.

Windows and Linux have no Find menu to strip.

### 6.5 Transcript scroll (option B — locked)

CoS asked A / B / C. The user locked **B**. Do not implement A (near-bottom pin) or C (freeze only while selecting).

Today desktop **forces** the newest message into view on send: `_scrollToBottom()` in `chat_page.input.dart` (post-frame after `sendMessage`) calls `ScrollController.jumpTo(0)` while generating or `animateTo(0)` otherwise. The list is reverse, so offset `0` is the newest. `_autoScroll` on `ChatPage` is always `true` and is never cleared when the user scrolls away — it is a dead gate, not a smart pin.

**Ship:** delete that send-time scroll. Delete `_scrollToBottom` and `_autoScroll` if nothing else uses them. Do **not** add a new listener that re-pins on `ChatService` notify (streaming rebuilds would fight option B). Leave `jumpToMessage` (Journal receipts) alone.

---

## 7. Find index — deferred

No visible-text indexer in this ship.

---

## 8. Web approach

Browser selection and Copy already work on ordinary DOM text. Do not replace that with a JS selection library.

- `user-select: text` on spoken body, expanded `.thinking-body`, thought-only hint, and banner text (`.dream-banner`).
- `user-select: none` on `.msg-actions`, swipe chrome, insight chrome, speaker labels. Do not set `user-select: none` on the transcript body.
- Right-click Copy is the **browser** menu. Ctrl/Cmd+C is the browser default. No custom clipboard polyfill on secure origins.
- **Do not** intercept Cmd/Ctrl+F. Browser Find is deferred-as-product; stealing the key would imply we own Find.
- No `<mark>` highlight helper, no Find bar, no Find Esc ordering.
- **Scroll:** remove the `useEffect` in `web_ui/src/pages/chat/useChatSession.ts` that `scrollTo({ top: scrollHeight })` whenever `state?.messages.length` or `streaming` changes. That is the token-by-token yank. Do not replace it with another pin.

Phone/PWA: select/copy stays native long-press select.

---

## 9. Accessibility and keyboard

| Key | Context | Action |
|---|---|---|
| Cmd/Ctrl+C | Selection in a bubble | Copy |
| Cmd/Ctrl+A | Selection in a bubble | Select that bubble body |
| Cmd/Ctrl+R | Composer (existing) | Regen — **unchanged** |
| Enter | Composer | Send — **unchanged** |
| Cmd/Ctrl+F | Anywhere | **Not our feature.** macOS menu item removed so the app does not claim it. Web: browser may still Find-in-page. |

- Screen readers still see bubble text as text, not as a single non-semantic paint.
- Update `docs/keyboard-shortcuts.md` in the **implementation** PR: chat bubbles are selectable/copyable; do **not** document a Find shortcut; note that macOS Edit → Find was removed because it did nothing. Not in this design-docs PR.

---

## 10. Interaction with existing chat gestures (must not steal selection)

Implementation checklist — if any item fails, the PR is incomplete:

1. Drag-select on speech does **not** toggle thought, queue a group speaker, swipe, regen, or delete.
2. Thought chevron still toggles; the expanded thought body is selectable.
3. Swipe and greeting chevrons still change the variant.
4. Banner long-press still offers delete; a text drag on the banner does not delete.
5. Edit / fork / delete icon hits stay reliable (the `IgnorePointer` border painter stays).
6. Streaming does not clear an in-progress drag unless the bubble’s text identity is replaced mid-gesture; if that is unavoidable, dropping the highlight is acceptable.
7. Composer selection/copy is unchanged.
8. Sending or streaming does **not** move the transcript viewport. Journal jump still does.

This is presentation/UX. 1:1 vs group must behave the same. Continue vs regen only matter because they change visible text. No generation-path twins. No Find jump / `GlobalKey` work in this ship.

---

## 11. Testing and poke script

### Automated (implementation PR)

Prove each new guard red before green. **New test files only** (editing existing tests needs `approved-test-change`).

**Desktop**

- Widget test: speech and expanded thought sit under a body-level `SelectionArea`; `StyledChatMessage` pumped alone does **not** wrap itself in `SelectionArea` (no nested islands).
- Thought-chip tap and swipe chevron still receive taps when a `SelectionArea` ancestor exists (hit-test, not golden-only).
- Banner long-press still invokes delete; the banner sentence is selectable.
- Hygiene: `MainMenu.xib` contains no Find submenu / `performFindPanelAction:`.
- Scroll: after a user-owned offset, a send or a streaming-token notify does **not** `jumpTo(0)` / `animateTo(0)`. Prove red on today’s helper, then green.

**Web**

- CSS/contract test: selectable body rules and `user-select: none` on speaker / actions.
- No Cmd+F intercept tests (we are not intercepting).
- Scroll: after a user-owned `scrollTop`, a new `messages.length` or `streaming` update does **not** call `scrollTo` / assign `scrollTop` to `scrollHeight`. Prove red on today’s effect, then green.

**Not required:** Find goldens, Find indexer tests, jump-key tests.

### Poke script (maintainer, ~15 seconds)

A sandbox cannot self-certify this. After the implementation PR:

1. Open a 1:1 chat with a long reply. Drag across a sentence → right-click Copy → paste into the composer. Confirm you did **not** copy the character name from the header.
2. Expand Thought. Drag across thought + speech in that bubble. Copy. Collapse Thought — thought text is gone and cannot be selected.
3. Group chat: tap a speaker name (still queues next). Swipe a reply with the chevrons. Drag-select the new body. On a Mac build: Edit menu has **no** Find submenu; ⌘F does not open a Find panel. Repeat select/copy in the web UI (browser Copy works). Browser ⌘F may still open the browser bar — that is acceptable and not our feature.
4. Scroll up mid-history, send a message (or wait for a streaming token). The viewport must **not** jump to the latest. Scroll down yourself if you want the new line. Same on the PWA.

---

## 12. Out of scope (literal)

- Implementing Find (in-app or OS) in any PR until a new lock.
- PlatformViews / native text hosts for Find or select.
- Implementing the feature in **this** docs PR.
- Changing `CLAUDE.md` beyond a one-line index pointer (none added).
- User-facing `docs/Rawhide.md` notes — those land with the implementation PR.

---

## 13. Open questions (short)

Locked. Defaults if the implementation PR does not get a new call:

1. **Cross-bubble select later?** No.
2. **Re-enable macOS Find menu when Find ships?** Yes — only then, and only if that future lock says in-app Find should own ⌘F (or a real `NSTextFinderClient`, which the investigation advises against).
3. **Scroll A or C later?** Not this ship. CoS listed A (near-bottom pin), B (never auto-scroll), C (freeze only while selecting). **B is locked.** Revisit A/C only with a new product lock.

---

## 14. Implementation PR (later — not this docs change)

One PR, desktop + `web_ui`:

- Bubble-body `SelectionArea` / web `user-select` per §6 and §8.
- Remove nested `SelectionArea` from `StyledChatMessage`.
- macOS Find submenu gone from `MainMenu.xib`.
- No auto-scroll on send or stream (desktop + web).
- Keyboard-shortcuts + Rawhide + tests + poke script above.

Do not grow `chat_service.dart` or any god file. Do not add Find state to `ChatPage`.
)
