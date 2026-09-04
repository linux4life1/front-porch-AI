# What's New

These notes feed the in-app "Update Available" dialog for stable releases on `main`.

## v1.3.2 — Make a Wish

- 🎂 **Calendar birthdays on character and persona cards** — your characters' birthdays
  are now visible on the card panel and on The Stoop. Gold/blue verified checks appear
  next to Discussion authors.

- 🌍 **Worlds that don't need weather** — a lorebook-only world can now opt out of
  climate entirely (`climateEnabled`). Quiet places stay quiet; no more mandatory
  sunshine and rain for worlds that never asked for it.

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
