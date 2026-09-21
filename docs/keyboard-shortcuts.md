# Keyboard Shortcuts

Front Porch AI keeps keyboard handling deliberately small. There are only a handful of real shortcuts — everything else follows your operating system's normal behavior.

Throughout this page: on macOS use **⌘ Command**; on Windows and Linux use **Ctrl**.

---

## The One That Matters

| Shortcut | Action |
|---|---|
| **Enter** | Send your message (while the message box has focus) |
| **Shift + Enter** | New line without sending |

That's the whole trick to writing multi-paragraph messages: hold **Shift** when you press Enter.

A stray Enter won't fire off an empty message. Sending only happens when the box actually has something in it (text, or a photo you attached), a character or group is open, and a reply isn't already being written.

---

## Regenerate the Last Reply

| Shortcut | Action |
|---|---|
| `Ctrl / ⌘ + R` | Rewrite the last AI reply |

This works while the message box has focus, and it's ignored while a reply is still streaming in. If you already deleted the last reply, it writes a fresh one from your last message instead. It behaves the same way in group chats.

Don't go hunting the chat toolbar for a matching button, though. The **Generate reply** button — the one whose tooltip spells out the shortcut — only appears in a 1:1 chat when your own message is the last one in the thread, which is the "I deleted the reply" case. For the everyday re-roll, the click equivalent is the small refresh icon (**Regenerate**) tucked under the last reply.

The keyboard shortcut is desktop app only — the browser/phone UI has the ⟳ buttons, just no hotkey for them yet.

---

## Editing a Message

Click the pencil (**Edit message**) on any bubble and the editor has its own two keys. They're printed in the bottom-right corner of the dialog so you can't lose them:

| Shortcut | Action |
|---|---|
| `Esc` | Cancel — if you changed something, it asks before discarding |
| `Ctrl / ⌘ + Enter` | Save |

These behave the same in the desktop app and the browser UI.

---

## The Stoop Messages

The mod-message composer on [The Stoop](user-guide.md#the-stoop-community-hub) works like the chat box:

| Shortcut | Action |
|---|---|
| **Enter** | Send the message |
| **Shift + Enter** | New line without sending |

---

## Standard Text Editing

Every text field in the app (chat box, character editor, story editor…) supports your system's normal editing keys:

| Shortcut | Action |
|---|---|
| `Ctrl / ⌘ + C` | Copy |
| `Ctrl / ⌘ + V` | Paste |
| `Ctrl / ⌘ + X` | Cut |
| `Ctrl / ⌘ + Z` | Undo |
| `Ctrl / ⌘ + Shift + Z` | Redo |
| `Ctrl / ⌘ + A` | Select all |
| Arrow keys, Home, End, PgUp, PgDn | Move around and select text |

Chat bubbles are the same: drag across the spoken line (and an expanded Thought) and use **Copy** or `Ctrl / ⌘ + C`. The name and buttons on the bubble are not part of that selection.

macOS **Edit → Find** (`⌘F`) is not in the menu. It used to be a leftover from the app template and did nothing on the chat canvas. The browser UI may still open the browser’s own Find — that is the browser, not Front Porch.

`Esc` closes most dialogs and `Tab` moves focus between controls — standard behavior on every platform. In the small single-line prompts (renaming a folder, searching for a model, typing a tag), **Enter** confirms instead of adding a line.

On macOS the usual menu-bar items are there too: `⌘Q` to quit, `⌘H` to hide, `⌘M` to minimize, `⌃⌘F` for full screen. One thing to know: **"Preferences…" (`⌘,`) in the app menu does nothing** — it's a leftover from the standard macOS app template that I never wired up. Settings lives in the left sidebar.

---

## In the Browser and on Your Phone

The web/mobile UI shares the same message keys (**Enter** sends, **Shift + Enter** makes a new line) whenever you have a real keyboard attached. On a phone you'll usually just tap **Send**.

A few extras that only exist in the browser UI:

| Shortcut | Action |
|---|---|
| `Esc` | Back out — dismisses the `@` mention or `/` command list while you're typing, and closes the Chat insight and conversation panels |
| `←` / `→` | Turn the page in the Porch Stories reader |

---

## Everything Else Is a Click

Actions like flipping between alternate greetings, Director Mode, forking a chat from a message, and voice input are buttons in the chat interface rather than hotkeys. Navigation (Home, The Stoop, Manage Models, Settings, User Persona, Worlds, Backups & Restore, and so on) lives in the left sidebar.

The app doesn't register any system-wide hotkeys — nothing triggers while Front Porch AI is in the background.

*If there's a shortcut you wish existed, tell me on [Discord](https://discord.gg/e4tET6rpdv) — this is the kind of thing user requests genuinely shape.*
