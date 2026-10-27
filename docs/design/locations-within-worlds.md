# Locations within Worlds

Status: **approved plan, not started.** Source: the Discord enhancement
thread "Support Locations as a finer-grain entity within Worlds" (Oct 2026)
and the follow-up on overloading lorebooks.

## 1. The ask

Authors build one detailed World (a town, a planet) and many places inside
it: town hall, academy, church, tea rooms. Every place has its own
description and lorebook. All of them share the parent's lorebook,
description and climate. Picking a place as the Setting of a chat should
bring the whole bundle: place prose, place lore, parent lore, parent
weather, without copying any of it into every place.

In one line: **a Location is a sub-World that inherits from its parent.**

Three concerns from the thread that this plan answers:

- **Budget.** The Setting block is always injected and budget-capped. A
  chain must not cost more than one world does today.
- **Depth.** Do locations have sub-locations? "It escalates quickly."
- **Transitions.** Moving between places mid-chat, including climate.

Plus two requirements that came out of review:

- A world must be able to hold several locales with **different climates**
  (Earth with its continents).
- **Overloading lorebooks**: a teacup in a palace and a teacup in a
  commoner's house trigger on the same key but read differently. The more
  specific place should win without the author copying worlds or toggling
  entries by hand.

## 2. What exists today

The UI already calls a World a **place**. A chat has place slots:

| Slot | Count | Owns |
|------|-------|------|
| Setting | 0..1 | weather and climate, the "Setting — where you are" prose, place traits |
| Lore | 0..N | lorebook entries only; never weather, never prose |

Where it lives:

- Model `lib/models/world.dart` (`World`), `lib/models/chat_place_slots.dart`
  (`ChatPlaceSlots`, `primaryWorldAllowsClimate`).
- Tables `Worlds`, `ChatWorlds` in `lib/database/database.tables.features.dart`;
  queries in `database.queries.worlds.dart`. Schema is v60.
- `lib/services/world_repository.dart` (cache, save, import, export,
  `resolveWorld`), `lib/services/world_store/`.
- Chat wiring `lib/services/chat/chat_service_wiring_injection.dart`
  (`_chatPlaceSlots`, `setChatPlaceSlots`, `setChatClimate`);
  `_worldDefaultBiome` in `chat_service_wiring_injection_leaves.dart`;
  weather gate in `chat_service_accessors_living.dart`.
- Prompt `lib/services/chat/prompt_injection/world_injection.dart`
  (`buildWorldInjection`, 600-char soft cap, trait lines beat description),
  called from `chat_service_generation_plan.dart` with the Setting only.
- Lore `lib/services/chat/lorebook_collection.dart` (`collectLoreEntryRefs`:
  chat book → group book → chat worlds → character books) and
  `lorebook_injector.dart` (SillyTavern inclusion groups: of the active
  members of a group exactly one injects, chosen sticky → prioritize →
  match score → seeded random).
- Clock judge `lib/services/chat/time_service/scene_time_evaluator.dart`:
  one post-reply model call reporting minutes, new day, days skipped and
  posture, tool call first then JSON text floor.
- Scene Guests: `cast_detector.dart` finds a named side character in the
  narration, `pendingGuestDetection` surfaces `SceneGuestDetectedDialog`,
  accept runs `SceneGuestFactory` and mints a lite card. The web snapshot
  carries the same flag.
- Desktop UI: Places sidebar `lib/ui/chat_components/sidebar/story_tools/
  chat_places_panel*.dart`; editor `lib/ui/pages/world_management/`;
  cards `lib/ui/pages/worlds/world_place_card.dart`; group wizard and group
  settings pick template `groups.world_ids`.
- Web: `web_ui/src/components/ChatPlacesSection.tsx`,
  `web_ui/src/pages/WorldsPage.tsx`; relay `lib/services/web/facade/
  world_facade.dart` + `routes/world_routes.dart` (`/api/worlds*`,
  `/api/chat/places`, `/api/chat/climate`).
- Portable format `lib/models/fp_world_package.dart` (`.fpworld` v1; the
  `lorebooks` array is already reserved for multi-book). The Stoop shares
  the same envelope.
- Tests: `test/services/chat/chat_places_primary_lore_test.dart`,
  `world_injection_test.dart`, `world_climate_injection_test.dart`,
  `test/services/world_repository_test.dart`,
  `integration_test/worlds_management_test.dart`, `WorldsPage.*.test.tsx`.

What the author can already do: one climate-off world per place attached
as Lore, the town as Setting. That gives the lore union but not the place's
own prose in the Setting block, not a one-tap bundle switch, and not a
library that reads as "town → its places".

## 3. Design: a Location is a World with a parent

No second entity, table, editor, relay or file format. One nullable
column, `worlds.parent_world_id`, and everything else is derived.

- A **Location** is a `World` whose `parentWorldId` is set.
- **Climate is inherited by default and may be owned.** A location with
  climate off takes weather, biome and place traits from the nearest
  climate-enabled ancestor. A location may switch its own climate on and
  becomes the climate author for itself and its descendants. So Earth can
  be a climate-on root carrying shared lore, each continent a child with
  its own biome, and each city under a continent inherits that continent.
- **The top-level world's switch covers every place in it.** With the
  root's climate off, nothing inside has weather, atmosphere or gravity.
  A place that owns a climate there keeps it saved but paused (the editor
  and the library card say so) and comes back when the root's weather is
  turned on.
- **Depth** is capped at two levels below the root in the UI (town →
  building → room). The engine walks any chain to the root; the editor
  refuses to make a child of a depth-2 location. The schema never needs to
  change if the cap moves.
- **Cycles** are rejected on save (a parent may not be the world itself or
  any descendant). **Deleting a parent re-roots its children** (parent
  cleared, climate left as it was) and tells the user how many. Lore the
  user wrote is never cascade-deleted.

### Resolution rules (the engine's contract)

With world `S` in the Setting slot:

1. **Chain** = `[S, parent(S), …]` up to the root, deduped by id.
2. **Climate, weather, traits** = the first climate-enabled world in the
   chain, provided the root is climate-enabled. None, or a climate-off
   root ⇒ weather off, exactly as a lore-only Setting today. The
   custom-climate dropdown id stays `world:<id of the climate author>`.
3. **Setting prose** = `buildWorldInjection(chain)`, leaf first, under the
   same 600-char cap. The location's own description wins the budget and
   the town's is truncated. A three-tier chain costs no more tokens than a
   single world does now. The editor shows the preview (see §5). Its
   atmosphere and gravity lines come from the rule-2 climate author only;
   the other worlds in the chain add prose.
4. **Lore** = chain books leaf first, then the Lore slot books. Existing
   dedupe by world id means a town attached both as ancestor and as an
   explicit Lore place enumerates once.
5. **Lore slot places may be locations** and bring their ancestors' books
   too. Still no prose, still no weather.

### Overloading: nearest place wins its inclusion group

`LoreEntryRef` gains a specificity rank set by `collectLoreEntryRefs`: the
Setting leaf is 0, its parent 1, and so on. `_pickGroupWinner` checks that
rank right after the sticky check, **but only among members whose worlds
are ancestors of one another** (one chain). Members from unrelated worlds
(a Lore-slot place that is not in the Setting's chain, a character book)
fall through to today's prioritize, scoring and random steps unchanged.
Among chain members the nearest place wins; ties at the same rank break
as today. This narrowing is what makes the upgrade a no-op for every
existing chat (see §8).

Authoring: put both "teacup" entries in inclusion group `teacup`. The
palace version injects whenever the palace or a room inside it is the
Setting. An ungrouped entry behaves exactly as today, and the group field
already round-trips through import and export, so the change is
nonbreaking.

Held back: implicit shadowing by identical keys with no group label. Zero
authoring, but it would silently hide a town entry meant to add detail. If
wanted later it is a per-location switch, never a default.

### Transitions

**Manual, always available.** Replace the Setting from the Places sidebar
or the web Places section. The Setting card's breadcrumb becomes a
dropdown of reachable places (self, parents, siblings, children) so a
by-hand move is one tap. Today's demote-on-replace stays: the old place
goes to the top of Lore, so its book remains live for the rest of the
scene. When the swap changes the climate author, `setChatPlaceSlots`
records a biome span from the current story day, so earlier days keep
their weather. That is the same `ChatBiomeSpans` machinery the climate
dropdown uses now.

**Suggested, confirmed by the user.** No new model call. The clock judge
gains one field, `scene_place`, whose only legal values are the ids of the
reachable places plus `same`. The field is sent only when Passage of Time
is on, the **global** Porch Life setting "Scene suggestions" (default off,
one switch covering moves and new places, same row shape as Passage of
Time) is on, and the Setting has relatives; otherwise the prompt is
unchanged. There is no per-chat switch: a chat that should never move is
one where the user taps Stay. The rubric
mirrors the days rule: report a move only when the reply narrates
arriving; a plan or a mention is not a move; missing or unparseable means
`same`. The service never applies the answer. It sets `pendingPlaceMove`
and the chat page shows a dialog in the Scene Guest style: "The model
thinks the scene has moved to the Tea Rooms. Move there?" with Move and
Stay. Move runs the manual path above. Stay remembers that place as
declined until the Setting next changes, so it does not nag. Because the
user confirms, a move is a user action: no undo chip, no per-message
rewind stamp, no Continue or one-shot special case. Web gets the flag
through the chat snapshot and shows the same dialog. One scene place per
chat in both 1:1 and group; split parties are out of scope. Director and
AFK turns do not run the clock judge and never move the scene.

### Starting place (required)

Attaching a world used to put the scene in the world at large. Every
top-level world now has a starting place inside it (any depth) where its
chats begin, chosen in the Worlds menu, never in the chat:

- **New World** (desktop dialog, web editor) requires naming one; it is
  created inside the new world (inheriting its weather) and starred in the
  same save. If the place cannot be saved, the new world is deleted again.
- **Edit World** picks among the world's places (or "A new place…");
  required whenever the world has places. An older world with none may be
  saved as it is.
- **Library star** on every place card moves it in one tap, like the
  canonical-avatar star. It cannot be cleared, only moved. A world with
  places and no valid star says so on its card.
- **World from Wiki / Character**: the Review step picks a written place
  or names a new one; Mint is off until it is set.
- **Starter worlds** ship with `default_place_id` (first place unless a
  world names `start`).

Stored as `placeTraits.defaultPlace` on the world row (no migration; it
survives weather-off worlds), exported as the additive envelope key
`default_place_id` and re-pointed at the imported copy on import.
`startingPlaceOf` (`world_chain.dart`) is the one rule: the starred place
while it is still inside the world, else the world. The save rule lives in
`world_store/world_starting_place.dart` (`saveWorldWithStartingPlace`,
`startingPlaceRejection`), shared by both editors, the relay and the mint.
The relay accepts `startingPlace: {placeId} | {name, description}` on
`POST /api/worlds` and stays lenient (the editors enforce the rule), and
`POST /api/worlds/default-place` moves the star.

It applies only where a world is *attached*: seeding a new chat from a
character's or group's worlds, back-fill, worlds added to a character,
and "Use as setting" in the attach picker (desktop and web). The starred
place takes the Setting even when it inherits its climate or the world is
lore-only. It never applies to a scene move (breadcrumb dropdown,
accepted suggestion), to "Add as lore", or to a fork, which keeps the
parent chat's slots.

### Minted places

The same field gains one more legal value, `new`, carried with a name and
a one-line descriptor, the same pair `DetectedCharacter` uses. It fires
only when the reply narrates arriving at a **named** place that is not in
the reachable list; an unnamed side street never qualifies. The dialog
offers Add and move, Just add, Ignore. Ignored names are remembered per
chat. Nothing is minted until the tap.

`PlaceFactory` sits beside `SceneGuestFactory`. Inputs: the name, the
descriptor, the narration lines where the place was portrayed, and the
parent chain's description and lore. Output: a child World under the
current Setting (or its parent when the depth cap is hit) with a short
description sized to the Setting budget, three to five lore entries, climate
inherited, and a `model-made` provenance marker. Where a parent entry
shares keys with a minted entry, the factory puts the new entry into that
inclusion group, so the palace teacup is written as the palace's version.
Persisted through `WorldRepository.saveWorld`, so name collisions, cycle
checks, export and the Stoop envelope behave as for a hand-made place.

Transport: the **eval transport** (native tool call first, then the JSON
text floor), not the World-from-Wiki tools gate, so a local KoboldCpp model
can mint. Guardrails: the same global "Scene suggestions" setting gates
the `new` value (no second switch), every mint is confirmed by a tap,
never climate on the fly, entry count capped, and a `model-made` filter
with bulk delete in the Worlds library.

## 4. Data and portability

- Schema v61: `ALTER TABLE worlds ADD COLUMN parent_world_id TEXT NULL`.
  Additive, no backfill, repair-ladder entry so a rerun is idempotent.
- `.fpworld` stays format 1 and gains an additive `locations: [ … ]` array
  on the root envelope, each item a world envelope with its own
  `climate_enabled` (inherit or own). Import creates child rows with fresh
  ids and `sourceId` provenance. Older apps ignore the key and import the
  root alone. A place is never exported alone or as a pruned branch: any
  export (file, relay, Stoop) carries its whole world, named for the world.
- Stoop: same envelope, so a shared WORLD card carries locations. Relay
  list and detail DTOs gain `parentWorldId`, `locationCount`,
  `climateAuthorId` (additive).
- `groups.world_ids` and character `world_names` keep accepting any world
  id, location or not.

## 5. UI (desktop and web in the same slice, parity law)

**Worlds library.** Only top-level worlds get cards; places never do, so a
library of many worlds stays a grid of worlds. A world with places shows
"N places · starts at X" in place of "Add a place inside"; it opens one
full-width panel beneath that row of cards (one open at a time, closed by
default) listing the places as rows, depth-first with rooms indented: the
starting-place star, name, one-line description, weather tag, entry count,
"Add a place inside" (not on a room) and a menu of Edit, Move to… and
Delete. Places have no Export: a world exports with its whole tree. The
header counts top-level worlds only. Filter: "model-made" (its places as
rows, with bulk delete). Multi-select action **"Move into…"** sets the
parent on many worlds at once, for authors who already built their places
as separate worlds.

**World editor.** Basics gains a **Part of** picker (none, or any root or
depth-1 world excluding self and descendants). With a parent set, the
climate section offers "Inherit from <parent> (<biome>)" or "Own climate";
the existing climate editor shows under "Own". Setting a parent never
flips the climate flag: a climate-on world opens with "Own climate"
already selected. When a parent is set on a world that existing chats use
as their Setting, the editor says what changes: "Chats set here will get
<parent>'s lore, and its weather if this place inherits." A
Setting-prose preview under the description shows what the chain emits at
the 600 cap.

**Places sidebar / web ChatPlacesSection.** Setting card shows the
breadcrumb ("Tea Rooms · Bletchfield") as the move dropdown and names the
climate author ("Weather from Bletchfield"). Attach picker lists roots with
children indented. Group wizard and group settings pickers get the same
indented list. No switches in the panel: one line notes that scene
suggestions are on and links to Settings › Porch Life.

**Settings › Porch Life.** One new row, "Scene suggestions", default off:
"When the story arrives somewhere nearby, or names a new place, the model
offers to move the scene or save the place. You confirm each one. Needs
Passage of Time." Same row on the web Porch Life settings.

**Dialogs.** `PlaceMoveDialog` in the `SceneGuestDetectedDialog` style, via
`showWarmDialog`, for both the move and the mint offers; web twin on the
chat page. Rendered text is plain strings; no enum names leak.

## 6. Delivery: eight PRs in strict order, each shippable alone

| # | Slice | Depends on | Guard that goes red first |
|---|-------|-----------|---------------------------|
| 1 | Model + schema v61 + `chainFor` / `climateAuthorFor` on the repository, cycle check, re-root on delete | — | `world_repository_test`: chain, cycle refusal, re-root; `repair_covers_ladder_columns_test` |
| 2 | Engine: chain climate (own or inherited), leaf-first prose, chain lore for Setting and Lore slots, specificity rank + nearest-wins group rule, biome span on author change | 1 | `chat_places_primary_lore_test`: location Setting gets ancestor weather, lore-only root keeps weather off, continent-level climates differ, grouped teacup flips with the Setting (1:1 and group), an unrelated Lore place's group member still wins by today's rules; `world_injection_test`: leaf wins budget; `lorebook_scanner_test`: ancestor books enumerate once |
| 3 | Desktop UI: Part of picker, inherit-or-own climate, grouped library, bulk "Move into…", breadcrumb dropdown, prose preview | 2 | `integration_test/worlds_management_test`: make a town, make a place inside, attach, see "Weather from <town>", move by dropdown; `layout_sweep` at 400 and 1440 |
| 4 | Web + relay twins of 3 | 3 | `WorldsPage.*.test.tsx` for the picker; journey in `web_ui/e2e/journeys.spec.ts` |
| 5 | `.fpworld` `locations[]`, Stoop ride-along, Rawhide notes | 1 | `world_repository_test` import group: round-trip keeps children, old envelope still imports |
| 6 | Confirmed scene moves: `scene_place` on the clock judge, `pendingPlaceMove`, dialog, declined memory, the global Porch Life "Scene suggestions" row, both shells | 2, 3, 4 | scene-time evaluator test: arrival sets the flag without changing slots, a plan does not, Move swaps and demotes, Stay is not re-offered until the Setting changes; dialog widget test; web journey |
| 7 | Minted places: `new` value, `PlaceFactory`, `model-made` marker, library filter + bulk delete, both shells | 6 | pure test of the tool payload decoder; the mint itself in the E2E journey (real model, no stub) |
| 8 | World from Wiki v2: tagged catalog, places in the scout, per-place lore, description and climate, review grouped by place, root + children on save, web twin and relay payloads | 1, 2, 5 | `world_from_wiki_test`: tagged characters land in their nation's book, a place with a climate hint gets its own biome, an untagged wiki still yields one flat world as today; `wiki_page_tiddly_test`: tags survive the Tiddly index |

Slices 1 to 5 are a complete, useful V1 on their own. If 6, 7 or 8 slip,
nothing ships half-wired. Slice 8 depends only on the data model and the
engine, not on the dialogs, so it can land before 6 and 7 if the wiki
case is the priority. Slice 7 carries the one real open risk, the
quality of minted lore on small local models; it is held behind the same
global switch, default off, and every mint is confirmed before it exists.

Path-complete matrix for slice 2: generation ✓; Continue reads the same
slots, no change; regen/swipe: slots are per chat, not per message, no
change; 1:1 ↔ group: slots are session-scoped for both, both asserted;
desktop ↔ web in slice 4. RAG, Journal, Growth, Pockets: N/A, no world
input. Slices 6 and 7 add no per-message state because the user confirms.

## 7. Decisions taken

- Depth cap two below the root, UI-enforced.
- Setting swap demotes the old place to Lore (today's behaviour).
- A location may own its climate; inheritance is the default.
- A climate-off root as Setting means weather off, as a lore-only world
  does today, and so does any place under it (owned climates pause).
- No implicit key shadowing in V1.
- No automatic travel without confirmation.
- One global switch for scene suggestions (moves and new places), in
  Porch Life, default off. No per-chat switches.

## 8. Migration and compatibility

Nothing changes for an existing library until someone sets a parent. An
existing world is a location with no parent.

**On upgrade (schema v61).**

- Every existing world gets `parent_world_id = NULL`: a root. Its chain is
  itself alone, so climate, Setting prose, lore and the 600-char budget
  resolve exactly as before.
- Chat attachments, Setting and Lore roles, character world links and
  group templates are not rewritten. No row changes.
- Climate flags stay as they are. Climate-on worlds keep authoring
  weather; climate-off worlds stay lore-only.
- Inclusion-group winners in existing chats do not change, because the
  specificity rule applies only within one ancestor chain (§3). A chat
  with a Setting and an unrelated Lore place sharing a group keeps today's
  sticky → prioritize → score → random pick. The slice 2 test pins this.
- Existing `.fpworld` files and Stoop cards import as before; they carry
  no `locations` key. A file exported by the new app and opened in an
  older app imports the root and drops the children, the same additive
  rule every world field has followed.
- The new column is additive, so an older build that opens the newer
  library file ignores it, as with every previous additive migration.
- Nightly / Rawhide data isolation (`FrontPorchAI-Beta/`) is unaffected.

**Adopting the system with places built the old way.** The common
pre-existing shape is a town plus several climate-off worlds attached as
Lore. It keeps working as is. To adopt: open each place and set "Part of"
to the town, or multi-select them in the library and use "Move into…".
No lore moves, no re-import, ids stay the same, so every chat that already
attaches a place keeps that attachment. Two things change at that moment,
and the editor copy says so:

- A climate-off place that now inherits gets the parent's weather in any
  chat where it is the Setting. An author who wants that place to stay
  weather-free picks "Own climate" and leaves climate off.
- The parent's lore now arrives through the place even in chats where the
  parent is not attached separately. That is the feature, but it is new
  lore in old chats.

Making a climate-on world a child never changes its weather: it opens with
"Own climate" selected and stays the climate author for its subtree.

**Chats whose Setting becomes a location later.** The next turn resolves
the chain; nothing is stamped on old messages, and regen of an old message
uses the chain as it is now, the same as editing a world's description
does today.

## 9. World from Wiki v2 and the Neokosmos test case

The auto world creator (`lib/services/world_from_wiki/`, wizard under
`lib/ui/character_creator/world_from_wiki/`, web `WorldFromWikiPage.tsx`,
relay `/api/worlds/from-wiki/*`) builds **one flat world**: the scout
proposes 20–40 cards into one lorebook, climate runs once from titles that
match a word list, and hub/leaf/crown roles plus inclusion groups shape
the book. It needs an overhaul to emit a root with locations.

### The test case: Neokosmos (`https://quietoak.github.io/NeokosmosWiki/`)

Pulled 2026-10-20. Single-file TiddlyWiki, 859 tiddlers, **88 text
documents**; the rest are images, video and audio.

| What | Count | Notes |
|------|-------|-------|
| Character pages | 52 | tagged `Characters` plus a nation / faction tag |
| Reustran Empire | 12 | e.g. Durandus, Dux Louvin l'Audice, Emperor Charles |
| Alnhama Republic | 11 | e.g. Aelric Stillhand, Bealdric, Ceolmund, Ceolwynn |
| Elves | 11 | Hrívë Court: a winter court in mist-bound forests |
| Picts | 9 | four tribe sub-tags: Bear, Boar, Thunderhoof, Shadowfang |
| Fresnia | 5 | |
| Atlantis | 2 | maritime |
| Cross-cutting tags | — | Knights 7, Royals 11, Cult of Sol Eternel 5 |
| World lore chapters | ~12 | Peoples of Neokosmos (one ~8k-char chapter per people), World Timeline (8k), Leylines and World Mana, Accounts of Faith, Geography chapters "Scope, Method" and "The Great Waters: Seas, Currents, and Maritime Boundaries" |

**There are no place pages.** Nations exist only as tags on characters
and as passages inside the Peoples and Geography chapters. The Geography
index page is a Tiddly list widget over the tag `A Measured World`.

Target output under the new system:

- Root **Neokosmos**, climate off, carrying the shared chapters (timeline,
  leylines, faiths, peoples) as its book.
- One location per nation: Reustran Empire, Alnhama Republic, Fresnia,
  Atlantis, the Elven realms, the Pictish lands; the four tribes at depth
  two under the Picts. Each holds its characters' cards and its own facts.
- Per-location climate authored from The Great Waters and the matching
  peoples chapter (winter forests for the elves, maritime for Atlantis,
  northern for the Picts). This is the Earth-with-continents shape of §3.
- Cross-cutting tags (Knights, Royals, the cult) stay inclusion groups or
  plain keys on the root, not places.

### Why today's wizard cannot produce that

- **The scout sees titles only.** `WikiStudioCatalog` carries titles, no
  tags. On Neokosmos the title list reads "Ceolwynn, Bealdric, Aelric
  Stillhand…" with nothing saying which nation they belong to. Tags are the
  only signal that places exist, and the Tiddly parser already has them in
  hand and drops them.
- **One book, one climate.** No notion that two regions differ.
- **Hub and leaf are already the right idea.** A hub is "a place or
  faction that may pull leaves". The overhaul promotes a hub from a
  lorebook entry to a child World.

### The overhaul (slice 8)

1. **Catalog gains tags** (Tiddly) and categories (MediaWiki). The scout
   prompt lists each title with its tags. `wiki_page_tiddly_test` pins that
   tags survive the index.
2. **Scout tool** gains a `places` array (name, keys, source titles,
   optional parent place, climate hint) and every card gains a `place`
   field naming one of them or the root. Roles and inclusion groups stay.
   The 20–40 card cap stays global.
3. **Review step** groups the shelf by place. Each place row has an "own
   climate" switch; signing stays per card. An unsigned place with no
   signed cards is dropped.
4. **Write** runs the existing lore batch per place, writes a short
   description per place (sized to the Setting budget), and runs climate
   per place that was flagged, instead of once for the world. Root climate
   becomes optional. Progress copy and abort cover the extra calls:
   Neokosmos goes from one climate call to about six.
5. **Save** creates the root and the children through `saveWorld` with
   parents set, so cycle checks, name uniqueness and export all hold. The
   preview shows the tree.
6. **Web twin** of the wizard and the relay scout/write payloads carry the
   same fields (additive; an older client sends no `places` and gets one
   flat world).
7. **Unchanged path:** a wiki with no tags or categories still yields one
   flat world exactly as today. That is a pinned test, not an assumption.

The wizard stays tools-only (`worldFromWikiToolsGate`), so this changes
nothing about which models can run it.

### The wizard's own context (2026-10-23)

The scout, the write batches, the climate call and the place profiles all
run inside one window the user picks in the Book step — *Context for this
wizard*: "Same as chat" (the chat's context setting) or 16K to 256K — on
the desktop and the phone (`/api/worlds/from-wiki/context`, status carries
`contextSize`, `chatContextSize`, `contextChoices`). Nothing in the wizard
hardcodes a reply size any more (`world_from_wiki_budget.dart`):

- The scout asks for the room the window leaves after its prompt. An index
  whose prompt would not leave `kWorldScoutReplyWant` is asked in parts and
  the shelves merge (dedupe by name, caps unchanged). A part the model
  cannot finish (finish_reason=length, a dropped incomplete call, a list
  that will not parse) is asked again in halves down to
  `kWorldScoutMinPart` titles; only below that is a part given up, and the
  status line says "asked in N parts, M cut off".
- Write batches pack up to eight cards while their articles leave
  `kWorldWriteReplyWant`; one card's articles are clipped so a card always
  fits. The climate articles are clipped the same way.
- A busy or unreachable server is reported, not retried on smaller parts;
  a reply the model never gave (prose, junk, nothing) is named for what it
  was, and only a real empty answer keeps "try a clearer premise".

### A world, not a cast list (2026-10-23)

The reference is the maintainer's hand-built *Bleach (TYBW)* world: one
always-on era card, eleven places (Soul Society, Seireitei, Rukongai,
Wandenreich, Silbern, Hueco Mundo, Karakura, the Royal Palace, Wahrwelt),
the factions, the timeline, the powers and items, and eight people written
as they are in that war — 34 entries of two dense sentences with alias
keys. Three things stood between the wizard and that shape:

- **The catalog.** "All pages" is alphabetical; capped at 500 it held a
  3,005-article wiki's A and B pages. A wiki bigger than the cap is now
  indexed by `Special:MostLinkedPages` (the API's `querypage=Mostlinked`,
  article namespace, one request) with the premise search in front, and
  categories fetched by title in batches of 25
  (`wiki_studio_lister.dart`, `mediawiki_categories.dart`). The review
  header says "top 478 of 3,005 pages by links". A small wiki keeps the
  complete listing.
- **The ask.** The scout prompt asked for a "cast list". It now asks for a
  setting bible in this order — era, places (nested, every place with its
  own hub card), factions, events, concepts/races/items, people last and at
  most a third — and every card carries a `kind` (`kWorldCardKinds`), which
  the review rows show instead of the engine's role word.
- **The review.** `auditWorldShelf` (`world_shelf_audit.dart`) checks a
  shelf of twelve or more cards: one era card, people at most a third (and
  never fewer than six allowed), at least four place or faction cards, and
  named places when a tagged wiki yielded place cards. A failing shelf gets
  ONE revise call with the findings, the first shelf and as much of the
  index as the window leaves; the result replaces the first only when it
  has fewer problems and at least twenty cards. The status line says
  "shelf revised: …" or "review: …" when the revise did not take.

Also: the wizard's tools check reads chat's verdict and never pings on its
own (`toolCheckFor(autoAsk: false)`); Setup's Next and Check now ask,
because on oMLX and LM Studio a ping is a model load.

**First live run (Kimi K2.6 via nano-gpt, 2026-10-23)** — 471-title ranked
catalog, a 40-card shelf that passed the audit unrevised (10 nested
places, 4 factions, 7 events, 11 concepts/races/items, 8 people), 23
minutes end to end. Two slips it showed, both fixed: a nano-gpt 502
("Upstream returned no tool call despite required tool_choice") dropped a
whole write batch, so `askToolsTwice` asks a stumbled write, profile or
climate call again and a batch that fails twice is asked once more as two
halves; and every place's own hub card had landed inside that place's
book, so `liftPlaceHubCards` moves it to the parent's (the root's for a
top-level place) on both the shelf and the write. The harness is
`test/live/world_from_wiki_live_test.dart` (`--tags wiki_live`).

**Live results (2026-10-23, the Bleach wiki, 64K).** Kimi K2.6 via nano-gpt,
fourth run with every fix: a 471-title ranked catalog, a 38-card shelf
that passed the audit unrevised (8 nested places, 4 factions, 8 events,
10 concepts/races/items, 8 people), every card written, 12:43 end to end;
each place has its own book and a 2–4 sentence description, people are
written as they stand in the war, keys are whole names. gemma-4-26B-A4B
on oMLX: the same catalog and shelf shape, but it answered the scout or a
write batch in prose two runs in four — the text floor read the JSON out
of the prose, and the thinking-off retry settled the rest; its entries
are thinner and less era-scoped. A hung profile call on nano-gpt (30
minutes, no answer) is what put the six-minute timeout in.

### The creator's loops (2026-10-23, plan)

The maintainer's rule: *reviewer passes and loops in the creator; you
can't hope it gets it right in one shot.* The shape is Porch Stories'
`StoryAgent.run` — generate, gate in code, review with a second call,
feed the objection back, bounded tries, keep the best valid answer so a
harsh reviewer never dead-ends — written again for the wizard, not
imported (`world_review_loop.dart`).

Knobs on the Book step, desktop and phone:

- **Depth** — Quick (~40 cards, gates only, no review calls), Full (~100,
  reviews on; the default), Deep (~200). Stored
  (`webSearchSettings.worldWikiDepth`), it sets the scout's card range,
  the fill rounds, the per-place minimum, how many top characters must be
  present, and the tries per loop (`world_from_wiki_depth.dart`).
- **Moment** — free text ("the night after the first invasion"). Every
  card, the era card first, is written as things stand then; what comes
  later is unknown and never stated. The reviewers check it.

Loops, in order:

1. **Shelf loop.** Generate (the parts runner, then revises), gate
   (`auditWorldShelf`: era, backbone, kinds, named places), review
   (`review_world_shelf`: nested right, residents where they belong, the
   Moment respected, nothing invented), feed back, tries by depth.
2. **Fill loop.** `auditWorldCoverage` reads the catalog the scout read —
   its most-linked pages and their categories — and names the gaps: top
   pages tagged as places that are not places, factions whose members the
   wiki lists but the shelf lacks, places under the per-place minimum,
   the top-N characters absent. Each gap is one focused call with its
   candidate titles; rounds by depth; stops at the card target.
3. **Entry loop, per write batch.** Gate in Dart (`world_entry_polish.dart`:
   160–330 chars, keys are this entry's names only, no single common
   words, the name is a key), review (`review_lorebook_entries`: as of the
   Moment, scene-usable — a person's look and manner and where they are,
   a place's sights and who holds it — nothing not in the article), revise
   only the failing entries with their findings; passing entries are kept
   from whichever try produced them.
4. **Profiles.** Gate only (2–4 sentences), the existing retry.

Writes on a remote provider run two batches at a time; local stays serial.
The run log (verdicts and notes per stage) rides the status line and the
scout/write responses as `notes`.

### The Review step before Mint (2026-10-23)

The maintainer's ruling: the human review is the **last step before
minting**, where the author gives input or direction and retriggers the
loop on that feedback. The Preview step became the Review step; the Shelf
step (tick-only) stays as the sign-off on names.

What the step does, on both surfaces:

- **Findings** — what the reviewers did this run: the shelf reviewer's
  note (sent back / revised), how many entries the entry reviewer
  rewrote, how many are still marked. From `WorldScoutResult.auditNotes`
  and the engine's `entryNotes` (`WorldEntryNote`: tries, passed, the last
  finding), which `reviewBatch` records per entry and the relay sends as
  `notes` in `world_wiki_done`.
- **Direction** — the author's note in their own words, with a scope: the
  cards it names (default) or the whole world. `triageDirection` asks the
  model to sort the note into rewrite / add / drop against the shelf
  (`direct_world_review`); when that gives nothing, every shelf name the
  note mentions is rewritten (`matchDirectionNames`). Rewrites go through
  `rewriteWithNote`: the note is the finding (`REVIEW FOUND: The author
  says: …`), the entry as it stands is the previous entry, and the entry
  reviewer reads what comes back — the same loop that wrote the world.
  Adds go through `writeOneCard` (the page by name when none is given).
  A pinned card is never touched.
- **Per entry** — text and keys editable in place (mechanics stay; the
  entry is rebuilt from its own JSON with the new text), the verdict line,
  Rewrite with a note (one card through `rewriteWithNote`), Drop, Keep.
  Per place: Add a card here.
- **Mint World** is the only save. The desktop keeps the tree in the
  wizard state (`WorldFromWikiReviewActions`); the phone keeps its own
  tree and sends only the named entries' current text with each action,
  so its hand edits survive a host rewrite, and the relay answers with
  only what changed (`world_wiki_review_done`: updated / added / dropped).

The sketch that was approved: the desktop and phone artboards of
"World from Wiki: Review before Mint" (private artifact, 2026-10-23).

### Full is sixty cards with rosters (2026-10-23)

The maintainer's ruling after the first loops run: Full aims at about
sixty cards. A faction's or place's members are named inside its own
card (the write rule and the entry reviewer hold it to that); only Deep
gives every member a card (`WorldWikiDepth.memberCards`), and the fill
loop's faction gap runs only there. The main cast (the wiki's most-linked
characters) still gets cards at every depth with reviews. Why: the
97-card Full run on Kimi K2.6 was 57 people, lopsided across two places,
and took the write past four hours; the hand-built TYBW world is 34
cards.
