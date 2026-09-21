# What's New

These notes feed the in-app "Update Available" dialog for stable releases on `main`.

## v1.4.0 — Toolbox

The drawer got real tools. Search, wiki, a second local model, Waifu’s OpenCode, and guests who can sit without taking the whole house.

- 🛠️ **Waifu Coder runs OpenCode like Kobold** — a private binary you start, stop, and update. Same Waifu seat. First sit-down still downloads if the closet is empty. Turning off “Check for updates” stops the launch GitHub check; a tap still checks or installs.

- 🔎 **They can look things up while talking** — web search rides the reply, not a silent pre-pass. Wiki is this character’s book (pick a saved wiki per chat), not a Google dump. Recipe cards live in the library `tools/` drawer for chat and Waifu. Same on the phone.

- ⚙️ **A second local model for feelings and journal** — a worker GGUF can sit beside chat and swap off the GPU. Pick Realism evals from the in-chat Model Settings sheet (same as chat, or a different host). Same on the phone.

- 👥 **Guests on the group couch** — `/create`, `/join --lite`, and `/scan` work in a group. They take turns and can be Away. Needs, diary, quests, and the feelings map stay off until you Promote that one person (`/promote Name` or the roster button). Turning a 1:1 into a group keeps guests as guests. A Full Front Porch `.fpchat` remembers Scene Guests and soft members. Old files still open. Same on the phone.

- 🎤 **The group porch mic** — `/speak` is who talks. Swap costumes from the group. `@Ana` asks her back from Away; just saying the name does not. `/join --full` turns a 1:1 into a group. Same on the phone.

- 🏡 **Porch Life is the factory default** — flipping Needs, Realism, Passage of Time, Objectives, or Afterglow in Settings does not rewrite the chat you have open. Lived-in meters stay. Use the sidebar for that one story. Same on the phone.

- 👜 **Pockets per person** — the switch sits on the Wearing / Carrying panel. Porch Life still turns the feature off for everyone. A group hand-off will not tuck items into someone you turned off. Same on the phone.

- 📜 **Leftover quests go stale** — if the story moved on, a quest or step can be marked stale-skipped instead of pretending you won. Same on the phone.

- 📥 **Drop cards on the home porch** — drag a PNG character card or a `.byaf` archive onto the home library. Several files at once is fine. A `.byaf` puts the first image on the portrait and the rest in the Avatar Gallery. Phone and browser import `.byaf` the same way.

- 📋 **Copy a reply like any other text** — drag across the words (including an open Thought) and Copy. Sending a new line no longer yanks the transcript if you had scrolled up. Same on the phone.

**Fixes that ride along**

- Error banners (“Backend is not running…”) are not saved as story.
- A quiet sit no longer invents hunger or a bathroom swing from the reply.
- A lore-only place stays lore — opening an older build against a newer library does not put weather back.
- Remembered lines keep a speaker nametag; a group turn keeps that speaker’s lore.
- OpenRouter tools are a real path (one POST per named eval), not a special-case guess.
- Unnamed / generic characters use they/them unless the card’s Sex field says otherwise.
- Regen can take an optional reason.
- Stoop: NSFW toggle refreshes the porch immediately; listing blurbs match the hub; the silver developer check shows in-app.
- Phone: attach a photo from the composer; changing the search key or evals GGUF path asks for your password.
- Windows and Linux caption buttons stay visible after the Mac title-bar fix.
- Thinking-only replies from some cloud models show up as speech instead of an empty bubble.
- Host switcher keeps the right API key and does not keep the last host’s model id.

For the complete list, see the GitHub release notes.

## v1.3.2 — Make a Wish

- 🎂 **Calendar birthdays on character and persona cards** — your characters' birthdays
  are now visible on the card panel and on The Stoop. Gold/blue verified checks appear
  next to Discussion authors.

- 🌍 **Worlds that don't need weather** — a lorebook-only world can now opt out of
  climate entirely. Quiet places stay quiet; no more mandatory sunshine and rain for
  worlds that never asked for it.

- ⚡ **Tool calls got faster** — the eval pipeline stops stalling on empty responses,
  retries smartly, and the three prefix-sharing judges now share one tools list, so
  structured evals land sooner on capable models.

**Major fixes**

- 🛡️ **No more quiet data loss** — replacing a portrait no longer wipes Journal,
  Growth, quests, or RAG; buried swipes stop deleting later entries; and forked
  1:1→group chats copy live pockets.
- 🎭 **Realism chips stay honest** — regen keeps its chips and needs deltas, and
  scoped reprocess only evaluates the needs you tick.
- 🕐 **AFK owns the clock** — idle turns stamp the chosen speaker's needs and set
  the clock before any post-reply eval can drift.

**Improvements**

- Sidebar chrome wraps cleanly across resolutions and pane widths; light-mode
  readability fixes for New Chat and Advanced Prompts.
- Stoop asset tokens are per-session and cleared on logout.
- Truncated or tiny model downloads are rejected and deleted on the spot.
- Dependency and CI action bumps throughout.

For the complete list, see the GitHub release notes.
