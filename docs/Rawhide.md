# Rawhide — What's New (Nightlies)

These notes feed the in-app "Update Available" dialog for Rawhide / cutting-edge builds.
**Only list what landed after the last shipped nightly.** Clear this section when a new nightly goes out — delete the old bullets; do not accumulate them.

Last shipped nightly: `rawhide.20260918.c11669b`. Everything below is unreleased.

## Recent improvements (unreleased — ships in the next build)

- 🖼 **Attach a photo from the phone** — the composer has an attach button. The model sees the picture the same way as on desktop.

- 💤 **Group away-time is about who actually speaks** — when Dynamic Responses fires in a group, the snapshot is that member’s day (their needs, their ambitions), not the leftover 1:1 card.

- 📖 **Lore keywords no longer make a local model re-read the whole chat** — triggered world facts sit after the transcript, so flipping a keyword does not throw away the cached prompt.

- 📋 **Copy a reply like any other text** — drag across the words (including an open Thought) and Copy. The name and buttons stay out of it. Sending a new line no longer yanks the transcript if you had scrolled up. An open Thought follows the newest tokens; scroll that pane up and it stays put. macOS Edit → Find is gone; it never searched the chat. Same on the phone.

- 👋 **Group friends can come back** — if someone wandered off (Away), `@Ana` asks her to check in this turn. Just saying “Ana, you coming?” does not drag her back. Or they quietly notice and rejoin on their own. People at work stay on the clock. `/speak` is the porch mic; `/join --full` converts a 1:1; swap costumes from the group. Same on the phone.

- 🪧 **Error banners are not story** — “Backend is not running…” and generation errors still show, but they are not saved and the next reply does not treat them as something that happened in the scene.

- 👜 **Pockets & Wardrobe per character** — the switch sits on the Wearing / Carrying panel. Porch Life still turns the feature off for everyone. A group hand-off will not tuck items into someone you turned off. Same on the phone.

- 📜 **Leftover quests step aside** — if the story moves on, a quest or step can be marked stale-skipped instead of pretending you won. A leftover step is skipped right away; a whole leftover quest waits for two “no longer relevant” checks (off / 1 / 2 / 4 in Porch Life). Same on the phone.

- ⚙️ **Porch Life is defaults, not the open chat** — turning Needs, Realism, Passage of Time, Objectives, or Afterglow off in Settings no longer writes that into the chat you have open. Lived-in meters stay. Use the sidebar for that one story. Same on the phone.

- 🤫 **A quiet beat can leave Needs still** — sitting together without eating, washing, or running around no longer invents a hunger or bathroom swing from the reply. If they already had the “they can smell themselves” beat, reopening the chat does not play it again until they wash. Same on the phone.

- 🌤️ **A lore-only place stays lore** — opening an older nightly against a newer library no longer puts weather back on a chat you had moved entirely to lore.

- 📥 **Drop cards on the home porch** — drag a PNG character card or a `.byaf` archive onto the home library. Several files at once is fine. A `.byaf` import puts the first image on the portrait and the rest in the Avatar Gallery. Phone and browser import `.byaf` the same way.

- 🏡 **Stoop NSFW toggle refreshes the porch** — “Show NSFW content” reloads The Stoop right away. You no longer have to leave and come back. After a model download, Model Selection lists the new GGUF without leaving the page. Switching hosts no longer keeps the last host’s model id. Same on the phone.

- 🔕 **No more “model loaded and ready” popup** — finishing a local model load (including mouth/worker swaps) no longer stacks that toast. A failed load still tells you.

- 🛠️ **OpenCode follows “Check for updates”** — turning that off in Settings also stops the Waifu / OpenCode GitHub check on launch. A tap still checks or installs. First sit-down still downloads if the closet is empty.

- 🪪 **Remembered lines keep a speaker nametag** — old RAG memories say who said them, and a group turn keeps that speaker’s lore. Same on the phone.

- 🔑 **Changing the search key or evals GGUF path on the phone asks for your password** — same stolen-session gate as the remote API URL.

- 🪟 **Windows and Linux caption buttons stay visible** — minimize / maximize still light up on hover after the Mac title-bar fix.

- 👥 **Guests can sit in a group without becoming full members** — `/create`, `/join --lite`, and `/scan` work in a group now. They take turns and can be Away like anyone else (a guest who walks off is marked Away; Needs and Realism still stay off). Promote them with `/promote Name` or the roster button. Turning a 1:1 into a group keeps the guests as guests. Same on the phone.

- 📦 **Guests survive a Full Front Porch chat share** — exporting a `.fpchat` now remembers who was a Scene Guest (1:1) or a soft group member. Importing onto the same open cast puts them back as guests. Old files still open. Same on the phone.
