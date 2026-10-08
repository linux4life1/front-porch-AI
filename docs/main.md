# What's New

These notes feed the in-app "Update Available" dialog for stable releases on `main`.

## v1.5.0 — Revenge of the Kobold

The engine room got rebuilt while you were chatting. Kobold insists you update.

- 🧠 **KoboldCpp, rebuilt so it just works.** Pick a model and go: KoboldCpp fits it to your graphics card by itself (GPU Layers is now **Automatic**), auto mode picks the batch size, and a plain **Local model** card in Settings shows what's loaded, lets you set the context, and says whether it fits, with a one-tap fix when it doesn't. Presets have a real editor (create, edit, rename, duplicate, delete, a plain-words summary, and a load estimate worked out from the model file itself). Switching models reloads KoboldCpp in place instead of restarting it, and an **Unload when idle** setting frees your graphics card after a quiet spell. The phone's Models page has the same card and preset picker.

- ⚡ **Replies start fast and stay fast.** A chat's place in KoboldCpp's memory now survives the Realism, Needs and memory checks between replies, so the next reply reads only what's new instead of the whole chat again. And the Local model card can **find the fastest settings for your computer**: it tries a few ways of running your model, keeps the quickest as a preset, and tells you how much sooner replies come.

- 🛟 **When KoboldCpp can't, you're told why, and nothing else breaks.** Out of graphics memory, an unreadable model file, a preset that can't run: a plain sentence on the computer and the phone, naming the largest context that fits when memory is the problem, and your working model stays up. ROCm cards get flash attention, with a safety net if the first reply dies. KoboldCpp older than 1.112 is refused instead of crashing.

- 🔁 **The app keeps KoboldCpp current.** At start, a KoboldCpp too old to run gets a box that updates it right there, or removes it if you use another backend. A newer release gets a gentler box you can put off for three days. Nothing shows if you don't use KoboldCpp.

- 🍽️ **Needs keep time with the story.** Hunger, bladder and energy wear down at a steady rate per hour of story time (each character's Pace still sets how fast) instead of the AI guessing a number; a skip never empties a bar, and sleep is something the story shows, so an all-nighter wakes up worn out. Characters bring a need up later and more gently, the bars turn amber at 40 and red at 25, and the chip under a reply shows the time and the scene apart (`1 hr 20 min · lunch`). The Refractory countdown after a climax runs on the story clock too.

- 📚 **Porch Stories Studio.** A second story engine beside Quick: it interviews your cast, double-checks every planning step, writes beat by beat with a continuity check, and patches only the line that slipped. A story made from a chat uses that chat's Journal and Growth Rings and stays true to how it played; a faithful retelling takes its genre, mood and length from the chat. Rewrite arc, a search box in Start from a chat, a run log that says where the time went, and Stories and Waifu Coder now take the whole window.

- 🎭 **An Expressions workspace in Image Studio, with prompt rules.** Expression packs get their own tab with their own description, source picture and target character; a stopped pack keeps its results until you re-roll, continue, import or reset it. Prompt rules put your words before and after every expression prompt, or find and replace inside it, saved as your defaults or for one pack, with the effective prompt shown before you start. Packs now start from the character's current portrait. On the phone too.

- 🖼️ **The Image Studio desk.** Create and Edit share one desk: connection, model, LoRAs, size and the advanced knobs in one place, with a readiness line that says what's missing. ComfyUI fixes on top: boxed-up subgraphs keep your settings, Reroute nodes survive a convert, saved Edit workflows get the real prompt and keep the Qwen strength you set, GGUF loaders are found on Comfy Desktop (and a server that already has them is asked once), and a half-finished comparison is skipped instead of shown broken.

- 🗂️ **A library you can grab.** Draw a box over the grid to pick cards, Shift-click a range, Ctrl-click one, then drag the whole pick into a folder or onto the folder path at the top. Select all and Select none, folders that follow your sort, a search that knows Everywhere from Top level only, and a tag window that scrolls. Export a whole character as a `.porch` file, or a set as a `.porchpack`, and import them back. Desktop for now.

- 🔢 **Chat reads better.** Every message has a number, from #1, and Journal and Growth Rings memories match them. Your messages are laid out like the character's, on the left; a switch in Settings → General puts them back on the right. Reading old messages no longer snaps you down, Thoughts stay out of the bubble, Generate reply at your own line scores it like a normal send, suggested actions stay with the message they were made for, imported and Enhanced chats keep their replies, and a brand-new chat starts as your default persona.

- 🪄 **The AI Character Creator has a Greetings step**, on desktop and phone: edit each greeting, rewrite it with one line of steering, delete an alternate or add one. Typing in the creator no longer lags on Windows.

- 📱 **The phone catches up.** Editing a message works again, and keeps its Thinking; taps that fail say why instead of doing nothing; a broken screen offers Reload or Back to library; the model button in a chat switches model and provider; long chats stay smooth while a reply streams; Japanese, Chinese and Korean keyboards no longer send mid-word; Stoop cards show the whole picture and load their thumbnails faster.

- 🤖 **xAI is a chat backend.** Pick it in Settings → Backend and sign in with SuperGrok to use your subscription allowance (unofficial, at your own risk), or use an API key as before.

- 🪟 **Desktop fixes you'll feel.** Windows no longer opens as a blank white window until you resize it. Text no longer smears or ghosts on any desktop while a local model works the graphics card (the app draws with its older renderer again). A file window that fails says so, with Try again, and exporting something whose name has a `:` or `?` opens the save window on Windows instead of waiting forever.

- 🍎 **Mac: macOS 13.3 Ventura is now the floor.** The memory-search runtime the app ships is built for it, so Monterey could never load it; nothing changes on Ventura and newer. Intel Macs can't run local models, and the phone's Settings now say so and offer the API path.

## v1.4.1 — KB5069420: Cumulative Porch Update

Round two. Restart not required.

- ⏰ **Needs follow the story clock.** Hunger, sleep and the rest move with the time the scene says passed, not with every message. A quick exchange leaves the bars alone and says "no needs affected." Needs off stays off, and on stays on, when you reopen a chat.

- 📚 **Export a lorebook, your way.** Pick which entries go into the file before you save it.

- 🌍 **Bring a character's lore into your Worlds.** Pick which of a character's lore entries to copy into a place in one of your Worlds, in one step.

- 🚩 **Stoop: report a real person.** Listings that use a real person can be reported from the card.

- 🔎 **Tell the character exactly what to look up.** End your message with `/search -- the name` to search the web, or `/wiki -- the name` to check the chat's wiki. Only the words after `--` get searched, so the character won't guess from the rest of your roleplay. Same on the phone.

- 🔁 **Force a lookup on regenerate.** The regenerate box has a new "Look this up" row. Pick Web or Wiki, type the exact words, and the new reply is written with that search. Web only shows when Web Search is on, and Wiki stays greyed out until the chat has a wiki. Same on the phone.

**Fixes that ride along**

- Windows: the Import, Export and folder pickers open again after an upgrade, even if the last folder you used is gone. A picker that never answers gives up after 10 minutes instead of hanging.
- Web search only looks at your latest message, not older lines.
- Bond and trust say "unchanged" when nothing moved, instead of vanishing.
- Regenerating with Realism off no longer shows Mood, Bond and Trust chips.
- "Where we are" is kept even when a save runs early.
- A long thread opens on its latest lines.
- In a group, you can delete a finished speaker's reply while the next one is still talking.
- "it's 7:15 pm" typed with a plain apostrophe sets the story clock, same as the curly one.
- Reprocess Needs hides needs you've turned off, on desktop and phone.
- Image Studio: stack up to eight LoRAs, filtered by base model; Draw Things LoRAs work; GGUF and saved ComfyUI workflows load properly.
- Image Studio: hitting Generate while a picture is already being made now tells you it's already running. Nano models load from the host, with an offline fallback.
- macOS: a bundled library is signed properly, so the app build seals cleanly.

For the complete list, see the GitHub release notes.

## v1.4.0 — Toolbox

New stage. New fighters. Same porch.

- 🛠️ **Waifu Coder joins the battle.** A private OpenCode binary you start, stop, and update. Same seat. First sit-down still downloads if the closet is empty.

- 🧰 **Same recipe cards as chat.** Drop JSON in the library `tools` folder. Opt in from the Waifu harness and they show up as tools. Skills are a separate Waifu-only drawer (`skills/<name>/SKILL.md`). Not Docker, not extra MCP servers. Same on Porch Life.

- 🔎 **A challenger approaches… the web.** Search rides the reply. The open internet, not a silent pass before they speak. Same on the phone.

- 📖 **Skip the handwriting.** A wiki can sit in for a lorebook, or next to one. Point at the site instead of copying the whole thing into cards by hand. They open the page when the scene needs it. Same on the phone.

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
