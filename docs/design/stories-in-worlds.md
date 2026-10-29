# Stories set in Worlds

Status: **research, not started.** Source: the maintainer's ask (Oct 2026)
to let a Porch Story use a Living World and its places as the setting, so
the story's events are grounded in the world's lore instead of invented as
it goes. Companion to [locations-within-worlds.md](locations-within-worlds.md)
(the place tree the story would read) and
[porch-stories-studio.md](porch-stories-studio.md) (the engine that would
read it).

## 1. The ask

An author builds a World: a town with its tea rooms and town hall, a
colony under an unbreathable sky, an estate with eleven house rules in its
book. Today a story about that town starts from a blank concept and the
model makes up the town again, differently, and keeps making it up scene
by scene. The World the author already wrote sits in another part of the
app and never reaches the story.

In one line: **a story picks a World the way a chat picks a Setting, and
every stage that imagines a place reads the World first.**

Three things the feature must do, in order of weight:

- **Ground the bible.** The status quo, the lore and the cast's "place in
  the world" come from the World, not from the concept alone.
- **Ground every scene.** When the planner says where a scene happens, it
  picks a place the World has, or names a new one inside it. When the
  writer writes the scene, it sees that place's own prose and the lore
  that applies there.
- **Never make the author copy anything.** No pasting a world's lore into
  the story's lore files. The World stays the source.

## 2. What exists today

**Stories have no link to Living Worlds.** Nothing under the story
services, models, pages or the web story pages reads `WorldRepository`,
a `World`, or `/api/worlds`. The "World" group in the Studio sidebar
(Cast, Relationships, Lore & continuity) is the story's own data.

What a story has in the way of a setting:

| Field | What it is | Where |
|-------|-----------|-------|
| `status_quo` | Free prose the foundation stage writes: "setting, rules, history and the normal world" | `lib/services/story/prompts/studio_bible_prompts.dart` |
| `lore[]` | `{topic, detail, related_to[], valid_from_act, valid_from_scene}`; written by the bible, grown by the archivist, and uploaded files chunked in as `related_to: ['file:<name>']` | `lib/models/story/story_elements.dart`, `story_lore_index.dart` |
| `scenes[].location` | Free text from the planner's `<setting>` tag ("Place, time of day, and the layout and objects that matter") | `studio_structure_prompts.dart`, `studio_parse.dart` |
| continuity facts of category `Place` | What the archivist noticed about places as the story went | `story_continuity.dart` |

How lore reaches the prose today: only the **Studio writer** gets it, as
the four best entries from an embedding search over the story's own
`lore[]` (word overlap when the embedding model is absent), with the query
"scene title. scene location. beat description" (`_loreFor` in
`story_pipeline/story_studio_prose.dart`). The Quick drafter, the Quick
whole-act writer and the Studio beat planner get **no lore at all**.

What a World has that a story could read (all in `lib/models/world.dart`,
`lib/services/world_chain.dart`, `lib/services/world_repository.dart`):

- A root with a description and a lorebook, and places inside it (two
  levels deep at most), each with its own description and book.
- A **starting place** (the starred one) where chats begin.
- A climate author somewhere in the chain: biome, season labels,
  atmosphere and gravity, with code-owned trait lines ("Gravity is low —
  bounding strides come easy…") that `buildWorldInjection` emits under a
  600-character cap, leaf first, in
  `lib/services/chat/prompt_injection/world_injection.dart`.
- Lorebook entries in SillyTavern shape: keys, content, `constant`,
  `group`, `order`. In a chat these fire by keyword scan; the story
  engine has no scanner and does not need one (see §3.3).

What already carries a world into a chat, and is the pattern to copy: the
chat's Setting slot (`ChatPlaceSlots.primaryId`), resolved through
`chainFor`, read live at every turn. Chats attach a world through
`startingPlaceOf`, so "attach Greenhollow" means "start in the
Conservatory". `test/services/chat/chat_places_primary_lore_test.dart`
pins the slot contract.

The seven starter worlds are the fixtures: every one has a root and
three places with prose; Greenhollow Estate also has eleven lore entries
(six on the house, the rest on its rooms). A wiki-built world at Full
depth is about sixty entries of 160–330 characters.

## 3. Design

### 3.1 One field, read live, lore copied once

`StoryProject` gains `world_id`: the id of a place (or root) in the
library, exactly what a chat's Setting slot stores. Picking a world stores
its starting place, as a chat does; picking a place inside stores that
place. `world_name` is stored beside it so the shelf and the Overview can
still name the world after it is deleted.

**The World is read live** for everything that is prose about the place:
the setting brief in the bible, the places list in the planner, the
"setting now" block in the writer. An author who fixes a typo in the
Conservatory's description mid-story gets the fix in the next scene,
which is how chats already behave.

**The World's lore is copied into `lore[]` once**, at bible time, each
entry tagged `related_to: ['world:<root id>', 'place:<owner id>']`, the
way uploads are tagged `file:`. Reasons:

- `StoryLoreIndex`, `knownAt`, the Lore & continuity page, the Director's
  `addLore` / `modifyLore` and the archivist's "new lore" all work on
  `lore[]` unchanged. Nothing new learns to search two sources.
- The bible's `<world_lore>` output **appends** to the copied entries
  (dedupe by topic, as `studio_parse.dart` already does for uploads) in
  place of replacing `lore[]`. The Quick architect does the same; today it
  overwrites.
- A later edit to the World's book does not silently rewrite facts the
  story has already built on. **Refresh from world** on the Lore page
  re-copies: entries whose `place:` tag matches are replaced, story-grown
  entries are kept.

An entry maps as `topic` = the entry's name or comment, falling back to
its first key; `detail` = its content. `constant` entries are also listed
in the bible's setting brief (§3.2) so the always-on facts are known
before any search. Keys, groups and order are not carried; the story
index is semantic, not keyword-driven.

**Macros.** A world written from a character carries `{{user}}` in its
entries by rule (world-from-character §3.3). Story code has no macro
resolver. On copy: `{{user}}` becomes the persona's name when the story
includes the persona, otherwise "the newcomer"; `{{char}}` becomes the
lead cast member's name when the story has a chat source with one
character, otherwise it is left and the writer is told what it means.
Rendered text (the Lore page) never shows a raw macro, per the style
rule.

### 3.2 Where the World enters each stage

The matrix. Every row is a stage that imagines a place today; a change
that skips a row says why. "Brief" is the new `StoryWorldBrief`, a pure
builder (chain + places + lorebook → text) with a soft character cap,
`kStoryWorldBriefChars`, pinned by a test like the 600 of the Setting
block. Trait lines are the ones `world_injection.dart` already owns.

| Stage | Engine | Today | With a World |
|-------|--------|-------|--------------|
| Foundation / Architect | Studio / Quick | concept, preferences, cast, canon | + `<setting_world>`: the root's name and description, the place tree (name + one-line description each, starting place marked), climate (biome label, its seasons, trait lines), `constant` lore. Rules: "The world is given. `<status_quo>` elaborates it and never contradicts it. Name places from the tree; you may add a place only inside it. Write `<world_lore>` only for facts the world does not already state." |
| Interview, Arc | Studio | status_quo carries the world | no change; status_quo is downstream of the brief |
| Acts, Sequences | Studio | storyInfo (title, concept, status_quo…) | no change beyond status_quo |
| Scenes / Scene weaver | Studio / Quick | `<setting>` free text | + `<places>`: the tree as names and one-liners. The reply gains `<place>` = the exact name of a place from the list, or `new: <name>` for a place inside the world. `<setting>` stays for time of day, layout and objects. `StoryScene` gains `place_id`, resolved by name; unresolved stays free text as today. "Vary the settings" becomes "move between the places the world has". |
| Beats | Studio | scene blueprint "Setting: location" | blueprint gains the place's own prose: `buildWorldInjection(chainFor(scene.placeId))`, leaf first, 600 cap, the same text a chat set there would see |
| Writer | Studio | `relevant_lore` from the index | + `<setting_now>`: the same 600-cap block for the scene's place. Index query unchanged. Entries tagged with the scene's place or its ancestors are ranked first (nearest wins), which is the chat's inclusion rule applied to a search |
| Drafter + Editor, whole-act writer | Quick | no lore, no setting beyond the location line | + `<setting_now>` and the top four lore hits, so Quick stops being the engine that forgets the world |
| Continuity review | Studio | ledger | + `<setting_now>`: a beat that puts a stove in a room the world says has none is a slip |
| Archivist | Studio | writes new lore to `lore[]` | unchanged; the story never writes to the World (§3.5) |
| Director `ADD_SCENE` / `modifyScene` | Studio | `<setting>` | sees `<places>`, may set `<place>` |
| Chat distiller | both | timeline from the chat | unchanged; the chat's Setting carries over at entry (§3.4) |

Prompt openings (`*Role` constants and the Quick opening sentences) do not
change: the integration fakes route on them.

**Budget.** Greenhollow's whole brief is under two thousand characters.
A sixty-card wiki world would be about fifteen thousand with every entry
inlined, so the brief inlines the tree, the climate and the `constant`
entries only, and the rest reaches the writer through the index. The
Engine step already shows real numbers for pacing; it adds one line,
"World brief: N places, M always-on facts, K searchable entries".

### 3.3 Why no keyword scanner

A chat scans the last messages for lorebook keys because it does not know
what the next reply is about. The story engine knows: it has the scene's
place, title and beat description before it writes a word. A semantic
search over that is the better retrieval, and it already exists. The
chat's inclusion-group rule (nearest place wins) is kept as a rank, not a
scan.

### 3.4 Entry points

- **New Story, Idea step.** A third card, *Where does it happen?*, with
  **Choose a world…** opening the same tree picker a chat uses to attach
  a place (`showAttachPlacePicker`'s rows: roots, places indented, "inside
  X" line). Picking a root selects its starting place with a chip "starts
  at The Conservatory"; picking a place inside selects that place. A
  Remove link clears it. Under it one Note: "The world's places and lore
  ground every stage. The story reads the world; it never changes it."
- **Start from a chat.** When the picked chat has a Setting, the world
  card prefills from it (`getChatWorldAttachments(sessionId).primaryId`)
  with the chip "from the chat". The same applies to **Turn Into a
  Story…** through `buildChatStoryProject`, which the dialog and the
  relay share, so both paths get it in one edit.
- **Worlds library.** *Write a story here* on a world card and a place
  row opens New Story with the world card filled. Optional slice; it is
  the discovery path for authors who build worlds first.

### 3.5 What the story does not do

- **Weather.** `WeatherEngine` needs a session seed and a story day; a
  story has neither. The brief carries the climate as texture (biome,
  seasons, traits) and the foundation may fix a season in the status quo.
  A story clock is its own feature.
- **Write back.** The archivist's new lore stays in the story. "Promote
  this fact to the world's book" is a natural follow-up and a one-way
  button, not part of this change.
- **Scene moves and minted places.** The planner names a new place inside
  the world in text; nothing is minted in the library. `PlaceFactory`
  could do it later from the scene's prose, behind a tap, as in chat.
- **Group templates and character world links** are chat concerns and are
  not read; the author picks the world for the story.

## 4. Data and portability

No schema change. The story is one JSON blob and every field below is
additive; `StoryProject.normalize()` repairs nothing new.

| Key | Type | Note |
|-----|------|------|
| `world_id` | string, nullable | a place or root id |
| `world_name` | string | display after deletion |
| `lore[].related_to` | gains `world:<id>`, `place:<id>` | beside `file:` |
| `scenes[].place_id` | string, nullable | resolved by name at plan time |

A deleted world: `chainFor` returns an empty chain, every brief and
`setting_now` block comes out empty, the copied lore stays, and the
Overview says "Set in Greenhollow Estate (no longer in the library)".
Nothing stops the run.

Web: `useStory.save` already round-trips unknown keys; the `StoryProject`
type and `draft.ts` gain the optional fields; the relay's full-save path
is a `fromJson` of the whole blob, so nothing else moves. Export (text,
Markdown, EPUB, audiobook) is unchanged; a story has no portable file.
Nightly / Rawhide isolation is unaffected.

## 5. UI (desktop and web in the same slice)

Both follow [porch-stories-ui-spec.md](porch-stories-ui-spec.md): Studio
tokens only, same labels on both surfaces, the local checker compares
them.

- **Idea step**: the card in §3.4, after "Or start from a chat". Row:
  world cover thumbnail (the chain's nearest cover), world name, "starts
  at X" or "at X" in muted text, Remove. Web twin in `IdeaStep.tsx` fed by
  `/api/worlds` (already returns `parentWorldId`, `defaultPlaceId`,
  `locationCount`); the tree order comes from `locations.ts`'s
  `planWorldLibrary`, which mirrors the Dart rules.
- **Engine step**: the brief line under the pacing numbers.
- **Shelf card**: "where you are · when" reads the world name.
- **Overview**: "Set in Greenhollow Estate · starts at The Conservatory".
- **Structure scene row**: the "cast · place · value → value" line shows
  the resolved place name; unresolved free text as today.
- **Lore & continuity, Lore tab**: a header card for the world (cover,
  name, N entries from it, **Refresh from world**, **Detach**) and a
  `from Greenhollow` chip on copied entries. Detach keeps the copied
  lore and clears `world_id`; the dialog says so.
- **Setup (after the fact)**: the Idea step is editable from the header's
  Setup, as every step is; changing the world mid-story re-copies lore
  the same way Refresh does, and the dialog says what changes.

No new setting, so `settings_parity_manifest_test` is untouched. No new
route, so the web sweep is unchanged; the journey gains "new story set in
a starter world".

## 6. Delivery: five PRs in order, each shippable alone

| # | Slice | Depends on | Guard that goes red first |
|---|-------|-----------|---------------------------|
| 1 | Model: `world_id`, `world_name`, `scenes[].place_id`; `StoryWorldBrief` (brief text, place list, lore copy with tags and macro resolution, cap); bible appends lore instead of replacing. **Built 2026-10-27.** | — | new `test/services/story/story_world_test.dart`: round-trip of the keys; Greenhollow's brief names the climate and three places under the cap and its eleven keyword entries copy as searchable lore (none is constant, so none is inlined); copied entries carry both tags; `{{user}}` resolves; `<world_lore>` appends and dedupes in both engines; Refresh keeps story-grown lore; a deleted world yields an empty brief |
| 2 | Prompts: `<setting_world>` in foundation and architect, `<places>` + `<place>` in scenes / scene weaver / Director, `<setting_now>` in beats, writer, continuity review and both Quick writers; place-first lore rank; chat Setting carried at entry. **Built 2026-10-27.** The Quick Beat Director was left alone: its prompt already carries the location and plans no prose. | 1 | new `test/services/story/story_world_pipeline_test.dart` (its own harness, so no old fake is touched): in both engines a scripted model names "The Kitchens" and the scene gets its `place_id`, a `new:` place keeps its name and no id, the beat and writer prompts carry the Kitchens' prose and list its two entries first, a world-less story's prompts are unchanged, and the Director's `<place>` resolves; `story_world_test`: lore rank nearest first and at most half the slots, `chainTo`, `resolvePlace`; `faithful_mode_test`: a chat with a Setting gives the story that world; the integration fakes' routing stays green unedited |
| 3 | Desktop UI: Idea card and picker, Engine line, shelf, Overview, header, scene row, Lore header and chips, Refresh and Detach. **Built 2026-10-27.** The story screens read the library through `worldsOrNull` so the pages still pump in tests and goldens that provide no world repository. | 1, 2 | new `test/ui/story_setup/story_world_card_test.dart`: picking a root starts at its starred place, picking a place inside starts there, an empty library says so, the pick round-trips through the project and reopens, a chat's world leaves with the chat; new `test/ui/story_studio/lore_world_card_test.dart`: the header line and the eleven chips, a double tap on Refresh writes once (held save), Detach confirms and keeps the copied lore, a gone world disables Refresh, plus the shelf/Overview/scene-row lines. Not added: an E2E stop in `story_studio_test` (no Linux runner in this session; the widget tests cover the same taps) |
| 4 | Web and relay twins of 3. **Built 2026-10-27.** Every word the PWA shows comes from the relay: `GET /api/stories/world?place=…|session=…` serves `StoryWorldSummary` (the same lines the desktop reads), `POST /api/stories/<id>/world/refresh` copies the book again, and the shelf list carries `worldName`; Detach is a plain save with `world_id: null`. | 3 | new `test/services/web/story_world_facade_test.dart`: the summary by place and by a chat's Setting, not-ok cases, Refresh keeps story lore, the shelf row's name; web: `draft.test.ts` round-trips `world_id`, `worldPick.test.ts` (lines, new-place rule, tags), `IdeaStep.world.test.tsx` (picker tree, pick a root or a place, Remove, a reopened story asks the relay, a gone world), `LoreTabs.world.test.tsx` (chips); journey "New Story can be set in a world" in `journeys.spec.ts` (runs in CI's web-e2e; not run locally). No new route, so the sweep is unchanged |
| 5 | *Write a story here* from the Worlds library, both surfaces. **Built 2026-10-27.** A menu item on the world card and the place row (desktop), an icon button on both (web); New Story opens on Idea with the world picked, a world at its starred place, a place at itself. | 3, 4 | new `test/ui/worlds/world_place_card_story_test.dart` (the menu items fire their callback and appear only when wired), new `test/ui/story_setup/story_setup_from_world_test.dart` (New Story from a world opens with the card filled); web `WorldsPage.story.test.tsx` (card and row navigate with the right place) and the journey "Write a story here on a world card" (CI's web-e2e; not run locally) |

Slices 1 and 2 are the feature for the engine; 3 and 4 make it reachable.
Path-complete matrix: this feature writes no chat state. Generation,
Continue, regen, Realism, Needs, Journal, Growth, Pockets, RAG and the
clock are untouched. Inside the story engine the sibling paths are Quick
↔ Studio (both covered in slice 2), new story ↔ chat-sourced story (both
in slices 2 and 3), plan ↔ Director edit (both in slice 2), desktop ↔ web
(slice 4).

## 7. Decisions proposed

- Store a place id, read the chain live; copy lore once with Refresh.
- Lore appends to the copy; the model never replaces the world's facts.
- No keyword scanner in the story engine; semantic search plus a
  nearest-place rank.
- Quick gets `setting_now` and lore too; it was the engine without any.
- Weather, write-back and minted places are later, each its own line.
- The story never changes the World.

## 8. Open questions and the recommendation for each

- **Live or frozen prose?** Recommend **live**. Scenes already written
  are prose and do not change; only scenes still to write read the
  world, so a mid-story fix to a place's description reaches the next
  scene, which is what a chat does. A snapshot would be a second copy
  that drifts from the library and needs its own Refresh. The lore copy
  (§3.1) is the one frozen part, and it is frozen because the story has
  built on it.
- **A story with two worlds?** Recommend **one world in V1**. The place
  tree already gives breadth inside one world, and a chat needs Lore
  slots because characters carry books; a story carries its cast as
  snapshots. The field name leaves room for `lore_world_ids` if a
  crossover is ever asked for.
- **May the planner invent places inside the world?** Recommend **yes,
  marked**. A sixty-scene novel in a three-place world needs more rooms
  than the author drew. A new place is `new: <name>`, shows a `new place`
  chip on the scene row, and is never minted into the library. Faithful
  mode forbids it, the way it already forbids new people.
- **Write back to the world?** Recommend **not now**. The archivist's
  facts are plot facts (what happened in this story), and a world's book
  is read by every chat set there, so a story's events would leak into
  unrelated chats. If it is wanted later it is one button on a lore
  entry, "Promote to the world's book", one way and one tap.
- **Where the picker lives.** Recommend the **Idea step**, not Cast: the
  world is part of the premise, and a chat-sourced story fills it from
  the chat's Setting before the author reaches Cast.

The sketch: the desktop and phone artboards of "Stories set in Worlds"
(private artifact, 2026-10-27): the Idea step on both surfaces, the
world picker, the Lore tab with the world header card, and the five
small places the world shows elsewhere (shelf, Overview, scene row,
Engine line, the world card's "Write a story here").
