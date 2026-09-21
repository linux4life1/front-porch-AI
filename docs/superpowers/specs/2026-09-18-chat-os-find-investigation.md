# Investigation: literal OS Find on Front Porch chat

**Date:** 2026-09-19
**Status:** Investigation only — no implementation, no Flutter-Find plan
**Branch / PR:** `cursor/chat-select-find-design-6e56` / #268
**Audience:** the user (linux4life1). Not a sales pitch for either approach.
**Related lock:** `docs/superpowers/specs/2026-09-18-chat-select-find-design.md` (approved in-app Find). This note asks whether that lock is worth keeping.

The question: **how bad is it if we try to use the operating system’s own Find** (macOS Edit → Find, Windows/Linux app Find, browser Ctrl+F) on the chat transcript, instead of a Flutter/web Find bar?

Short answer up front: on **Flutter desktop it is not free, and making it real is a rewrite of the transcript**. On the **React PWA it already works**, with the wrong search scope. Those are different products wearing one name.

---

## 1. What “OS Find” actually is

There is no one OS Find. Four different machines, four different contracts.

### macOS

AppKit’s find is a **first-responder action**, not a system-wide search of pixels.

- Menu items send `performFindPanelAction:` (older) or `performTextFinderAction:` (10.7+).
- The first responder is supposed to own an `NSTextFinder` and set its `client` to something that implements `NSTextFinderClient` (string access, replace, highlight rects, scroll).
- `NSTextView` does this for free (`usesFindBar` / `usesFindPanel`). A plain `NSView` that only paints a bitmap does **not**.
- Front Porch already ships the stock Flutter macOS Edit → Find submenu in `macos/Runner/Base.lproj/MainMenu.xib` (Find… = ⌘F, Find Next = ⌘G, Find Previous = ⇧⌘G, Use Selection for Find = ⌘E, Jump to Selection = ⌘J). Those items target `performFindPanelAction:` on the first responder (`target="-1"`).
- Today that first responder is Flutter’s view / text-input plugin. It is **not** an `NSTextFinderClient`. ⌘F from the menu is a polite no-op (or a beep), not a search of the chat.

macOS does **not** OCR the window. Spotlight and “Find in page” in Safari are different features. The menu we already show is the NSTextView-shaped one.

### Windows

There is **no OS Find panel** for a generic HWND.

- Notepad, Word, and Edge each implement their own dialog/bar.
- Win32 `EM_FINDTEXT` exists only if the control is an Edit / Rich Edit.
- Flutter’s window is a compositor surface (Impeller / GLES / Vulkan). Ctrl+F is just another key unless the app handles it.
- Front Porch’s `windows/` runner has **no** Find accelerator and no Edit → Find menu.

“Use OS Find on Windows” means **write a Find UI** (custom) or **embed a native text control** that already has one (Rich Edit / WebView2). It is not a checkbox.

### Linux

Same story as Windows, with GTK names.

- `GtkTextView` / `GtkSourceView` have search. A `FlView` is a GL area. GTK’s find has nothing to read.
- Front Porch’s Linux runner has no Find menu.
- Official **GtkWidget platform views are not a shipped public API** (Flutter issue #188375 — design/prototype track, not “drop in GtkView”).

### Web browser (our `web_ui`, not Flutter web)

This is the only surface where “OS Find” is real and already on.

- Chrome / Safari / Firefox / Edge: Ctrl/Cmd+F opens **Find in page**.
- It searches the **DOM text** of the current document, highlights matches, next/prev, match count.
- It does **not** ask the app. It does **not** know “bubble body vs chrome.”
- Our PWA is React + real HTML (`.bubble`, `.thinking-body`, insight aside, composer). That is searchable today.
- The Flutter **desktop** app is not this. Flutter-web CanvasKit (if we ever used it for chat) would be as blind as desktop; we do not ship chat that way.

---

## 2. Does Flutter desktop get OS Find for free with `SelectionArea`?

**No.**

Current engine / framework reality (not a wishlist):

- `SelectionArea` is a Dart widget over `SelectableRegion`. It owns mouse/touch selection, a context menu (Copy / Select all), and platform-looking handles. Source: `packages/flutter/lib/src/material/selection_area.dart`. There is **no** find client, no `NSTextFinder` hook, no Win32 `EM_FINDTEXT`, no GTK search.
- Selectable text is laid out and painted by Flutter’s text engine onto the raster surface. The OS sees a texture, not a string.
- The macOS embedder’s `FlutterTextInputPlugin` **subclasses `NSTextView`**, but only as a **field editor / accessibility backing for focused `TextField`s** (composer, dialogs). Chat bubbles are not text fields. That hidden `NSTextView` does not contain the transcript and must not be treated as one (recent engine work is still about making `copy:`/`paste:` hit the Flutter editing model, not about Find).
- Semantics / VoiceOver can read Flutter text. `NSTextFinder` does **not** search the accessibility tree. Screen-reader “find” is a different feature.
- Wrapping more of the bubble in `SelectionArea` (the approved select/copy work) **still does not** light up Edit → Find. You will be able to highlight and copy, and ⌘F will keep doing nothing.

So: **select/copy and OS Find are not a package deal in Flutter.** SelectionArea solves the first. It does not touch the second.

---

## 3. What native path would be required

To make *literal* OS Find work, the thing being searched has to be a native text client. Options, with what they actually are:

### A. Host the transcript in native text views (the “real” OS Find path)

| OS | Host | Find you get |
|---|---|---|
| macOS | `AppKitView` → `NSTextView` (or a custom `NSTextFinderClient` view) | AppKit find bar / panel |
| Windows | Child HWND Rich Edit or WebView2 — **no public `Win32View` API** | That control’s Find |
| Linux | `GtkTextView` — **no public `GtkView` API** | GTK search, if you built the embed yourself |

Flutter’s own docs on macOS platform views (today): **not fully functional; gesture support is not available**; hybrid composition syncs the raster thread with the platform thread; `AppKitView` is documented as **expensive**. Windows/Linux platform views are an umbrella design issue, not something this repo can flip on.

You would also write Swift / C++ / GTK, keep them in version lockstep with bubble features, and violate the project’s “no PlatformViews for Find” out-of-scope line for a reason: this is the only honest native path.

### B. Fake an `NSTextFinderClient` in front of Dart text (macOS-only costume)

Keep painting in Flutter. Implement `NSTextFinderClient` in the embedder: `string` = concatenated visible bubble text from Dart, `scroll` / highlight callbacks hop back to Flutter (`jumpToMessage` + a highlight overlay).

That **is** the in-app indexer plus extra FFI. Users get a macOS-looking bar. Windows and Linux still have nothing. You still write the hard parts (visible-text rules, thought-open flags, virtualized reverse list). You do **not** get OS Find “for free.”

### C. WebView2 / WKWebView the whole chat

Render the transcript as HTML so the embedder’s find-in-page works. That is **reimplementing desktop chat as `web_ui` inside a platform view**, with the gesture and theme problems of A, plus a second chat stack. The PWA already *is* that HTML chat, without stuffing it into the Flutter process.

### D. Do nothing native

⌘F on macOS stays the dead menu item. Ctrl+F on Windows/Linux does nothing. Web keeps browser Find.

---

## 4. Concrete damage to Front Porch (if we take path A)

This is the transcript we would have to give to native text: `StyledChatMessage` (RP quote/action colors, per-chat font, Reading Size scaler, markdown image split), collapsible Thought, thought-only hint, Chance Time / Dream banners, swipe/greeting chevrons, edit/fork/delete, TTS, realism chips, inline generated images, theme `CustomPaint` borders (`IgnorePointer` — already a shipped tap-swallow bug), group name tap-to-queue, reverse virtualized `ListView.builder`, Journal `jumpToMessage` + page-owned `GlobalKey`s, streaming token rebuilds, Waifu sharing the same `MessageBubble`.

| Area | What breaks |
|---|---|
| **Markdown / rich text** | Native views want `NSAttributedString` / RTF / Pango. Our coloring is Dart `TextSpan`s from `tokenizeChat`. You reimplement that tokenizer on three native sides or accept a plain dump (quotes and `*actions*` lose color). Reading Size and Google Fonts become native font maps. |
| **Inline images** | Flutter widgets (`ExternalImageWidget`, `InlineChatImage`) with consent and zoom. Native = text attachments or HTML `<img>`. Consent, right-click Save, and Image Studio “send to chat” all get a second path. |
| **Thought expand** | Desktop Thought is Flutter state (`_thoughtOpen` / pin). Native Find either (a) only sees expanded text and you still need a Flutter chevron, or (b) inlines think into the `NSTextView` and we lose the collapse product. Browser-style “search closed `<details>`” is the opposite of the approved visible-only lock. |
| **Swipe** | Chevrons are Flutter `InkWell`s. A native text view eating the bubble means chevrons sit *beside* a platform view that (on macOS) **does not have working gesture forwarding**. Swipe-vs-select was already the hard Flutter problem; platform views make it worse, not better. |
| **Theme** | Bubble fill, opacity, and the decorative painter live in Flutter. An `NSTextView` will not run `CustomPaint`. Per-chat presets either stop at the native hole or you paint a fake bubble *around* the hole and fight clipping. |
| **Performance** | Chat already rebuilds the visible list on streaming. One `AppKitView` per bubble is the expensive case the Flutter docs warn about (raster ↔ platform sync). One giant `NSTextView` for the whole history means every token rewrites a huge attributed string and **throws away virtualization**. Long chats are why we have `ListView.builder` + `jumpToMessage` paging. |
| **Selection + gestures we already planned** | The approved select work is “lift `SelectionArea` around the body; keep detectors on chip / header / chevrons.” A platform view **replaces** that subtree. You re-solve select, long-press-delete on banners, group-name tap, and the IgnorePointer border, now across a Flutter/native hit-test seam the macOS embedder does not fully support. |

None of this is theoretical polish. It is the same class of bug that already shipped (theme painter swallowing taps; `GlobalObjectKey(msg)` crashing on chat switch). Native holes multiply that class.

---

## 5. Hybrid: Flutter select/copy + OS Find only — is it coherent?

**On desktop: no.**

- After SelectionArea lift, copy works. OS Find still has no client. The user can highlight “porch” and press ⌘F / Ctrl+F and **nothing in the transcript highlights**. That is worse than today, because we trained them that the text is “real” enough to select.
- macOS specifically: Edit → Find is **already in the menu**. Shipping select/copy without either (a) a Flutter Find bar that steals ⌘F, or (b) ripping the dead Find menu out, leaves a labeled lie in the menubar.
- A “hybrid” that implements `NSTextFinderClient` on macOS and nothing on Windows/Linux is **not** hybrid. It is a macOS-only Find with a Dart backend, plus two platforms still dead. Parity law fails.
- A “hybrid” that is “select in Flutter, Find in the PWA only” is coherent **as a deferral** (“desktop Find later / never”) but it is not OS Find on desktop.

**On web: yes, and it is the default.** Browser select + browser Find already coexist. The fight is scope (next section), not mechanism.

---

## 6. Web: allow native browser Find vs a custom bar

This is the one place OS/browser Find is **not** a fantasy.

**Allowing browser Find (do nothing / do not `preventDefault`):**

- Works today on every keyboard browser. Zero Dart. Zero new UI.
- Searches **the whole document**: header, Cast bar, composer, Conversations/Stats chrome, and the **insight aside** on desktop-width (it is mounted, not `display: none`).
- Closed Thought: `<details class="thinking">` still contains `.thinking-body` in the DOM. Browsers typically **still find** that text. That **violates** the approved “collapsed thought is not on screen → not searchable” lock.
- Speaker labels (`.msg-speaker`) are outside `.bubble` and **will** match. Product lock said names outside the bubble are out.
- Hover-only `.msg-actions` may still be in the accessibility/layout tree; some browsers will hit “Regenerate” / swipe counts.
- No active-match styling we control; no porch-amber; no “N of M” we own. Users already know the browser bar. That is a plus, not a minus.
- Phone: no Cmd+F. Native long-press select remains. A Find button was already optional in the lock.

**Custom bar + `preventDefault` on Cmd/Ctrl+F:**

- Steals a **working** browser feature. Power users will hate that if the custom bar is worse (and it will be, for a while).
- Lets us match desktop and enforce visible-only (ignore aside, ignore closed `<details>`, ignore speaker labels).
- Costs a hook, indexer, highlight `<mark>`s, Esc ordering vs drawers, and composer-not-insert-`f`.
- We must still leave browser Find available if our bar is not focused? No — once we `preventDefault`, it is gone for that key. Users can still open Find from the browser menu unless we go further.

Honest split: **web native Find is cheap and slightly wrong. Web custom Find is work and slightly ruder.** The approved spec picked custom for parity. If desktop Find dies, web custom Find loses its reason.

---

## 7. Pain score (1 = easy / fine, 10 = do not)

Literal **OS / browser Find as the product**, not “a Flutter bar that looks native.”

| Surface | Score | One-line why |
|---|---|---|
| **macOS Flutter** | **8** | The Find menu is already wired and hits a view that cannot search a canvas; making it real is `NSTextFinder` + PlatformView (gestures incomplete, expensive) or a Dart indexer in a native costume. |
| **Windows Flutter** | **9** | There is no system Find for our HWND; public platform views are not there; Rich Edit / WebView2 is a second chat. |
| **Linux Flutter** | **9** | Same as Windows, plus no shipped GtkView; `FlView` is a GL area GTK cannot grep. |
| **Web PWA** | **3** | Browser Find already works; the pain is over-search (sidebar, chrome, closed thought), not a missing engine. |
| **Desktop “hybrid” (SelectionArea + leftover OS Find)** | **7** | Copy starts working; ⌘F/Ctrl+F stay dead; macOS menu keeps advertising Find. Confusing, not cheaper. |
| **Full native transcript (path A, all three desktops)** | **10** | Reimplement the bubble stack in three toolkits, break swipe/theme/stream/virtualization, and two of the three hosts are not even a public Flutter API. |

For calibration — **in-app Flutter/web Find** (the approved lock), if we later do it: about **4–5**. Real work (indexer, jump, gestures, web intercept), but it stays in Dart/TS, reuses `jumpToMessage`, and does not fight the engine. That is not free. It is smaller than path A.

---

## 8. Recommendation (plain English)

**Do not chase literal OS Find on the Flutter desktop app.** It is not sitting behind `SelectionArea`. The macOS Find menu is a leftover from the Flutter template. Windows and Linux never had an OS Find to give us. Hosting `NSTextView` / Rich Edit / GTK text for the transcript would blow up Thought, swipe, themes, streaming, and the 500-line widget split — and on Windows/Linux the embed API is not even a thing we can honestly schedule.

**Select/copy in Flutter is still worth doing** and does not require this decision. It is a different feature. If Find stays undecided, ship select/copy and either (a) intercept ⌘F with a small “not yet” or (b) remove / disable the macOS Find menu items so we stop lying. Leaving the dead menu is the worst of the cheap options.

**On the phone/browser UI, allowing native Find is reasonable** if you are willing to accept “the whole page,” including the insight column and collapsed thought HTML. That is the opposite of the visible-bubble lock, but it is the Find users already have. A custom web bar is justified mainly so desktop and web feel like one product.

**If you still want Find on Windows and Linux** (most of the desktop installs), it will be an in-app bar. There is no OS to ask. Pretending macOS AppKit Find is “the product” leaves those machines behind.

**If you only care about macOS feeling native:** a Dart search plus an `NSTextFinder` costume is possible and still a project. It does not help Windows/Linux and still needs the same visible-text indexer as the Flutter bar. I would not spend that glue unless the in-app bar ships first and you hate how it looks on a Mac.

No code in this note. No Flutter-Find implementation plan until you pick: **in-app Find (keep the approved spec)**, **select/copy only (defer Find)**, or **web browser Find + desktop select only (asymmetric)**.
)
