# What's New

These notes feed the in-app "Update Available" dialog for stable releases on `main`.

## v1.1.1 — Linux hotfix

- 🐧 **Fixes Linux installs that couldn't open their database** — v1.1.0 shipped without its bundled SQLite engine, so Linux users saw "libsqlite3.so is missing" and were told their database was corrupted. **Your data was never actually damaged** — the app simply couldn't open it. Updating fixes it, and your chats are exactly where you left them. Affects every Linux package (`.deb`, `.rpm`, AppImage, tarball and the AUR build); macOS and Windows were never affected.

- 🔒 **This can't happen again** — the release pipeline now refuses to publish a Linux build that can't reach its database engine, so a missing library is caught before it ever reaches a download page instead of on your machine.

## Highlights — v1.0

Front Porch AI hits **1.0** — the biggest update ever. Everything below has been proving itself on the nightly builds for months and lands in stable at once.

- 🏡 **The Stoop — a community character hub, built right in** — browse, share, and download character & group cards without leaving the app (or from any browser at hub.frontporchai.app). Whole group casts travel with their lorebooks and realism state intact. Opt-in, 18+, and the rest of the app stays 100% local.

- 📔 **Characters keep a real diary now (The Journal)** — promises made, things they learned about you, moments that mattered — each memory stamped with the feeling behind it. Strong memories linger; faint ones resurface when the moment calls them back. Read it, edit it, pin the ones that matter. Nothing ever leaks between chats.

- 🌱 **Growth Rings — character growth you can actually see** — instead of silent personality rewrites, every real change becomes a visible "ring" with receipts you can tap to jump to the moment it happened. Recurring growth becomes permanent; stale growth fades into a viewable past.

- 🎭 **One chat, a cast that changes** — turn any solo chat into a group in place with `/join`, wave someone off with `/exit` (undo included), and collapse back to a clean 1:1 — realism, needs, and memory carry across both ways.

- 🧭 **Lorebooks work the way their authors wrote them** — import SillyTavern / Chub / NovelAI / AgnAI / RisuAI books through a preview wizard; conditional triggers, timers, chains, variety groups, and stateful macros (`{{setvar}}`, `{{roll:d20}}`…) all actually run.

- 🖼️ **The Image Studio was rebuilt** — pick a subject and go; generate full **expression packs** from one portrait (with an AI vision quality check), paint the current scene with `/image` right in chat, use reference images with a denoise slider, and connect **ComfyUI** with zero node graphs.

- 📸 **Send your character a photo — they actually see it** — vision models react to your pictures in character; any GGUF can gain sight via its mmproj file; and a fully local Photo Understanding helper covers text-only models. No cloud.

- 📱 **The web & phone app was rebuilt** — a proper installable app in the same warm look: chat, characters, stories, images, and the full Stoop from your phone. Much faster over slow connections, and it heals itself after your phone sleeps.

- 🛋️ **The warm-porch redesign** — the whole app now speaks one cozy design language (goodbye neon accents), and light mode finally looks right everywhere.

- 🧠 **The Realism Engine got deeper and far more reliable** — readings arrive as structured tool calls on capable models (chips stop stalling), characters hear their state as natural language instead of stat dumps, group chats match 1:1 exactly (including genuine hostility and needs catastrophes), intimacy recovery feels human, and self-chosen goals become real quests with steps.

- ☕ **Your character keeps living while you're away** — turn on Dynamic Responses (or type `/afk`) and they'll quietly get on with their day — a meal, a nap, a shower — with time and needs following along.

- ⚡ **Faster, and honest about what it's doing** — long local chats reply dramatically sooner (reading phase ~15s → ~1s), the status bar shows real progress ("Reading prompt — 43%"), your sampler settings and stop strings actually reach the model, and thinking models genuinely think on local KoboldCpp.

- 💾 **Smarter local backups replaced Cloud Sync** — rolling 30-minute + daily snapshots written by the database engine itself, with one-click restore. Old PCs without AVX2 are now supported automatically, too.

For the complete list, see the GitHub release notes.
