# What's New

These notes feed the in-app "Update Available" dialog for stable releases on `main`.

## v1.4.0 — Toolbox

New stage. New fighters. Same porch.

- 🛠️ **Waifu Coder joins the battle.** A private OpenCode binary you start, stop, and update. Same seat. First sit-down still downloads if the closet is empty.

- 🔎 **A challenger approaches… the web.** Search rides the reply. The open internet, not a silent pass before they speak. Same on the phone.

- 📖 **Skip the handwriting.** A wiki can sit in for a lorebook, or next to one. Point at the site instead of copying the whole thing into cards by hand. They open the page when the scene needs it. Same on the phone.

- 🃏 **Recipe cards, in the drawer.** One tools folder in the library, for chat and Waifu.

- ⚙️ **New fighter: the second local model.** Feelings and journal can sit beside chat and swap off the GPU. Pick them from the in-chat Model Settings sheet. Same on the phone.

- 👥 **Guests have entered the match.** They take turns until you Promote that one person. Needs, diary, and quests stay off until then. Same on the phone.

- 🎤 **The mic is live.** `/speak` picks who talks. `@Name` calls someone back from Away. Just saying the name does not. Same on the phone.

- 🏡 **Porch Life is the default stage.** Flipping a switch in Settings does not rewrite the chat you have open. Same on the phone.

- 👜 **Pockets, per fighter.** The switch sits on the Wearing / Carrying panel. Same on the phone.

- 📜 **Quests can time out.** If the story moved on, a leftover quest goes stale instead of pretending you won. Same on the phone.

- 📥 **Drop in.** Drag a PNG card or a `.byaf` onto the home library. Same on the phone.

- 📋 **Copy, like any other text.** Drag across the words, including an open Thought. Same on the phone.

- 🖼️ **Image Studio grabs their templates.** Comfy Create runs the graph they ship. Remote Studio can be Nano or OpenRouter without moving chat. Same on the phone.

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
- Opening a chat lands on the latest messages. Older history loads as you scroll up. Follow streaming replies (Settings → General, on by default) stays with the newest words only if you are already at the bottom — scroll up to stop. Same on the phone.
- Afterglow no longer keeps them limp for the whole cooldown. The first reply after a scene can still feel wrecked. After that, tired and comfortable follow Needs. Same in a group.

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
