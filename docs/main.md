# What's New

These notes feed the in-app "Update Available" dialog for stable releases on `main`.

## v1.7.0 — A Porch to Remember

The porch remembers now — your half-typed line, your cast, your sounds, your settings — and the groups grew up doing it.

- ✍️ **A half-typed message survives.** Close the chat, switch characters or restart the app, and the line you never sent is still in the box when you come back. Start a brand-new chat with that character and it inherits the draft. A sent line never haunts the reopen, and deleting the chat deletes its draft with it. Desktop and phone.

- 👥 **Groups start from the card.** A new group's members begin with their character card's bonds, trust, mood and Needs — the values that make them them — not a neutral placeholder everyone resets to. What you set in the wizard lays over the card, and a moved baseline starts its bar there.

- 🧭 **The group wizard, all seven steps, on the phone.** The phone's new-group wizard walks every step the desktop does, openings are written where the group actually meets, and a guest you `/join` brings its own starting place.

- 🗺️ **One world per group, one world per card.** Every group gets its own world with a chosen starting place, character cards carry one world at the place you pick, and a group chat can be the source of a Porch Story.

- 🛠️ **Members you can actually fix.** Edit Character edits a group member in full, desktop and phone. The member card shows what's running for that member, the editor shows the group's switches and sets where each member starts, away included. Edits save to the member, voices and `@Name` find members by id so a namesake can't steal the line, and no member stays the main character after answering.

- 🔐 **Porch Life, one gate.** The Realism Engine has one gate on every chat, and Needs and Afterglow have their chat switches back behind it. Turning Afterglow on asks what to do with your existing chats; turning it off hides Lust and recovery and keeps them.

- 🌙 **Afterglow, member by member.** Each group member carries their own Afterglow switch and their own Recovery block, desktop and phone, and a chat's own Afterglow flag survives saves and carries across.

- 😊 **Mood, on the face.** A character's mood, bond, trust and Needs paint what they own: a ring around the portrait that burns, breathes or jitters by mood tone, a bond glow behind it, and needs bars that throb in their own hue when one is in trouble. The latest reply wears its stamped mood at the full level, and a new Appearance row chooses how far it goes. The phone paints the same.

- 🌇 **The sky follows the story clock.** The Ambient Stage blends its washes by the minute instead of snapping at day boundaries, walks a sun across the day and a moon wearing its phase across the night, brings out stars after sunset and glows the horizon at dawn and dusk. Thick weather only dims them, and it costs no frames when nobody's talking.

- 🔊 **Real field recordings, and yours too.** Scene sounds move from synthesized placeholders to ten looping location recordings with thunder that ducks under speech, and starter worlds arrive with sensible ambience. Your own sounds get a first-class home: a custom-sound library that auditions, assigns and reuses your files across every world without re-uploading.

- 🎡 **The Chance Time wheel spins for real.** The chaos event runs on the stage engine: a pointer that clicks over every peg, bulbs and sparks at wheel speed, a landing shake and a reveal in the event's own key — never festive on a bad one. The phone finally gets the wheel.

- 🎛️ **Generation presets that follow the model.** Save your generation settings as presets and link one to each chat model: switching models applies its preset or that model's recommended samplers, from its own metadata or the provider defaults, with an undo. No more carrying the last model's settings into the next.

- 🖼️ **The Studio keeps what you make.** Every Create and Edit result stays on a Recent shelf with its prompt, style, tab and model — 50 by default, or 200, keep all, or off — and starred pictures are never trimmed. Desktop and phone read the same shelf, and inserting into a chat copies the picture first so trimming can't break a chat.

- 💾 **A backup that's really complete.** Snapshots now hold the library, your settings and your own files — portraits, pictures, galleries, worlds, voices, stories — each stored once and shared between snapshots. A restore brings back custom prompts and everything else, all-or-nothing, desktop and phone; API keys come along only if you say so. Settings save atomically, so a crash can't wipe them.

- 📥 **Backyard AI imports, deeper.** `.byaf` chats arrive whole: every regenerated reply becomes a swipe that opens on the one you last looked at, the opener becomes the first bubble, and the importer asks which persona you were talking as so the lines carry the right name.

- 🗂️ **A sidebar that rearranges — and stays put.** Drag any tab or accordion leaf into the order you want, the wheel still scrolls while a tab is in hand, orders sync to the phone, and a Lock layout pill means nothing moves by accident.

- 🧹 **Smaller fixes.** Journal and Our Story list newest first. Bubbles show the persona that actually sent the line. The phone's `/join` picker lists characters in folders too. A minted place never re-mints a place that already exists. Windows gets an ordinary title bar in Light mode and follows the light/dark switch. Manual Reprocess moved out of the thumb zone on touch screens.

## v1.6.1 — Cloudy with a Chance of Porch

Worlds got places, the sky got weather, and the clock learned to read.

- 🗺️ **Places inside worlds.** A world now holds its towns, buildings and rooms. The Worlds grid shows worlds only, each saying how many places it holds and where its chats start, and opening one lists its places right under it: star the starting place, add, edit, move or delete, with rooms tucked under their building. A place shares its world's lore and weather unless you give it its own. Deleting a world takes its places with it. Characters and groups link whole worlds. Places travel inside `.fpworld` files and Stoop cards. Desktop and phone.

- 🚶 **The scene moves with the story.** The Places breadcrumb in a chat moves the scene, and when the story names somewhere new, a Scene suggestion offers to go there. One tap turns a named arrival into a real place inside the world.

- 🌍 **Seven starter worlds, with pictures.** Seven ready-made worlds with places inside, each with a painted cover, from the frozen Whitereach to the lantern-lit market in Harborside.

- 📖 **World from Wiki, rebuilt, and World from Character.** The wiki wizard reads a whole world, not a cast list: pick how deep to go and the moment in the story, watch a progress panel that says what it's doing, and review every card before you mint (rewrite, drop, keep or add). Full depth writes up to sixty cards, with factions carrying their members. A second source builds a world from a character and its chats, as Facts only, Faithful or Creative.

- ⛈️ **The Ambient Stage.** The chat takes on the story's weather: a tint, then rain with depth, snow, drifting clouds, layered fog and lightning. A place with a picture paints it behind the bubbles, and moving between places plays the weather on the way. Scene sound adds weather loops and thunder that duck under speech. Bubbles turn see-through while the scene paints. All of it is in Settings → Appearance.

- ⏩ **Time skips read like you meant them.** A short model read now works out how far "we slept eight hours" or "two weeks later" moves the clock, and where it lands. End a message with `/skip 8h`, `/skip 2d` or `/skip morning` for an exact jump. When a skip is unclear, a "Did time pass?" question offers the best guess and the alternatives. Skips the reply writes count in full, and a night the reply carries everyone through wakes them rested, in groups too.

- 📥 **A new model downloader.** Search tuned for roleplay models, with filters, a model card, every file in a repo (split and subfolder quants and vision add-ons included), a real check of what context fits, the best fit picked for your card, an optional HuggingFace token for gated models, and faster, safer downloads. The Model Manager stays smooth on Windows while it downloads.

- 💬 **Prompts that stay put.** A saved-prompt picker for both prompt slots, with the built-ins read-only. One Group system prompt covers every group, and every group turn uses one tidy layout. Director rules survive custom prompts, and converting a 1:1 to a group keeps your persona.

- 🧹 **Smaller fixes.** Click a generated portrait in the creator to see it full size. Gemma 4 on Vulkan can run flash attention, with a warning. Linux no longer aborts at launch when GStreamer's playbin is missing. Porch Life's Afterglow switch is the one Lust gate. One-Shot Eval sits above the tool pill, and a card's Needs switch reaches chats that already exist. A guest you `/join` into a 1:1 shows its Promote button, and promoting it keeps the chat's world and place. On the phone, an older chat update never overwrites a newer one.

## v1.6.0 — Fifty Shades of Porch

Paint it your colour, call the shots, and let the story keep its own time.

- 🎨 **Make the porch yours.** A new **Appearance** tab in Settings has eight app themes, light and dark, a custom accent colour, fonts and corner styles. The phone and browser app follow the desktop theme, light mode included, with a per-device override.

- 🎬 **Director Mode, rebuilt.** `/director` steps you out of a group and runs the scene from the chair: cue a line, whisper to one character, set a scene goal, bring in a narrator, give the run a budget and beats, and let a judge keep character-to-character turns honest. Pause and Resume, typed lines that stick, and manual **Away** and **Back** for any cast member. Same controls on the phone.

- 🔎 **Find in chat.** Ctrl+F (⌘F on a Mac) opens a find bar that searches the whole chat, not just what's on screen. Desktop and phone.

- ⏩ **Time skips that make sense.** A big skip gets a narrator card that bridges the gap. Skips the reply or a `/narrate` beat describes now move the clock, more ways of saying "later" are understood, and a long skip lands at the time of day it names. Needs live through a day-plus skip before the reply, and Journal heat cools by story days.

- 🎯 **Goals keep up with the story.** Objectives sync with what actually happened, a character feels and remembers how a goal ended, a goal they keep pushing gets a rest, and a goal you set is never set aside.

- 😤 **Mood with bite.** A mood now has a cause, holds for a while, eases off, and pulls on how the character behaves. The Mood and Lust chips explain themselves when you hover or tap.

- 🌙 **Afterglow (18+).** What happens after a climax now follows the character: a recovery profile on the card, a tenderness window, satisfaction that fades on a curve, both sides read by the judge, and closeness that bonds deeper when it was wanted. Chance Time respects the refractory lock, and an opt-in grey mood afterwards is there for darker stories.

- 🪄 **A better Character Creator.** A Profile step that fills in the full Front Porch card, interview questions you can edit, reorder and voice, templates saved as files, and an "Interview this character" switch to skip the interview. Desktop and phone.

- 🖼️ **Images in bulk.** Image Studio opens from Home and has a **Batch** tab for generating many pictures at once and reviewing them. A Remote API option with host tiles, per-host sizes and Grok Imagine; expression intensity controls; and each image backend keeps its own model and LoRA picks.

- 🧠 **KoboldCpp, smarter.** Pick a chat template in a preset, with a warning when the template doesn't fit the model. The app remembers the last model on each backend, can send Realism checks to a worker on another PC, and leaves more of your graphics card for the model while it writes. The prompt progress bar tells the truth, and the check progress can be minimized.

- 💬 **See behind a reply.** Inspect the exact prompt behind any reply, see other words a KoboldCpp reply weighed and rewrite from one, pick a prompt source per chat when you start it, add global prompt additions, and see "Your chats together" stats on a character's Details tab. Characters and personas convert into each other.

- 🛟 **No more lost edits.** Editors for characters, groups, personas, worlds, the Data Bank and Growth Rings ask before you leave with unsaved changes, on desktop and phone.

- 🎲 **Chaos with more range.** More varied events, a frequency setting, an 18+ gate, and a spicy switch that stays saved.

- 🧑‍💻 **Waifu Coder that finishes.** Turns always finish and undo as a whole, she stays in character, switches really reach OpenCode (Plan is read-only), and the pinned OpenCode is checked before it installs.

- 📱 **The phone catches up again.** Settings in the desktop's sections, the per-chat prompt picker, Pockets receipts and Director chips.

- 🧹 **Smaller fixes.** The update check says "check failed" when it can't reach GitHub instead of "up to date", tap the version in the sidebar to copy it for a bug report, Next names who will really speak in a group, Create World saves once on Windows, and the app leaks less memory going Home.

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
