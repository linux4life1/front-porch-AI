# World from Character

Status: **proposed, not started.** Source: the maintainer's ask (Oct 2026)
to build a Living World from a character's card and, optionally, one of
that character's chats, the way a Porch Story can be built from a chat.
Companion to [locations-within-worlds.md](locations-within-worlds.md),
whose §9 describes the World from Wiki wizard this feature rides on.

## 1. The ask

A character's card already describes a place: the scenario, the greetings,
the example dialogue, the card's own lorebook. A long chat with that
character has named streets, shops, rivals, a season, a war. Today the
only way to turn that into a World is by hand, one entry at a time, or to
find a wiki that happens to cover it.

In one line: **the World from Wiki wizard gets a second source, a
character and one of their chats, and nothing else about it changes.**

Two rulings from the conversation shape the design:

- **Entry point is the Worlds page from Home, not a chat.** No chat-tools
  menu item, no "set as this chat's Setting" at the end. The minted world
  lands in the library like a wiki world does and the user attaches it to
  a chat the normal way.
- **UX stays in step with World from Wiki.** Same wizard chrome, same
  steps, same Shelf and Review, same progress panel, on the desktop and the
  web app in the same change.

## 2. What exists today

Three features each do a third of the job.

**Chat to story.** `buildChatStoryProject` (`lib/services/story/
faithful_mode.dart`) is ONE builder shared by the desktop dialog and the
relay (`/api/chat/tools/to-story`). The Chat Distiller
(`lib/services/story_pipeline/story_chat_distiller.dart`) loads a session's
messages, cuts them into chunks of fifty, folds in that stretch's Journal
cards and Growth rings as confirmed facts (`StoryChatMemory`), and asks the
model for an event timeline per chunk, merged at the end. The Story setup's
"Start from a chat" picker (`lib/ui/story_setup/chat_source_picker.dart`,
`web_ui/src/pages/story/setup/ChatSourcePicker.tsx`) lists 1:1 sessions
with a message count and a `short chat` chip under `kShortChatMessages`;
the rows come from `StoryChatHistory.chatSources()` and the relay's
`/api/stories/chat-sources`.

**World from Wiki.** `WorldFromWikiEngine` (`lib/services/world_from_wiki/`)
is scout → write → review → mint. It touches the wiki through exactly two
calls: `listStudioTitles` (the index: titles, tags, whether it is ranked by
links) for the scout, and `getArticleFull(title)` for the writer, the entry
reviewer and the climate call (`joinSources`). Everything after the index
is source-agnostic in spirit: the shelf shaped like a setting bible, cards
with a `kind` from `kWorldCardKinds` and a `place`, the places tree, the
Review step with findings, direction and per-entry rewrite, the progress
panel, the context budget, the tools gate, Mint World through
`WorldRepository.saveWorld`. The wizard is five steps (Setup, Book, Shelf,
Write, Review); the Book step is four cards (The world, The wiki, How deep,
What to make). Web twin `WorldFromWikiPage.tsx` with `WorldBookStep.tsx`,
`WorldShelfStep.tsx`, `WorldReviewStep.tsx`, `WorldProgressPanel.tsx`;
relay `/api/worlds/from-wiki/*` (`world_from_wiki_facade.dart`).

**PlaceFactory.** `lib/services/chat/place_factory.dart` already mints a
child place from six narration lines with a description sized to the
Setting budget and three to five entries, marked `madeBy: model`. It
proves the prompt shape holds on local backends through the eval
transport.

Also relevant: `World.linkedCharacterId` and the "auto-imported from
character card" description prefix are a retired design, and
`WorldRepository._saveWorld` strips both on every save ("Places only,
never re-create character-linked clones"). This feature must not revive
them. `World.sourceId` is the provenance column import already uses.

## 3. Design: a second source behind the same engine

### 3.1 The source seam

The engine takes the concrete `WikiSearchService`. Slice 1 puts an
interface in front of the two calls it makes and changes nothing else:

```
abstract class WorldSource {
  String get label;                                  // "bleach.fandom.com", "Yoruichi's chat"
  Future<WikiStudioCatalog> catalog({String? seedQuery});
  Future<String> article(String title);
}
```

`WikiWorldSource` wraps the wiki service. The scout prompt, the write
batches, the budget, the review loop and the places write are untouched;
`world_from_wiki_test.dart` stays green without edits, which is the pin
that the seam is a pure refactor.

### 3.2 The character and chat source

`CharacterChatWorldSource` builds the same catalog shape from two inputs,
a `CharacterCard` and an optional session id.

**Card sections are titles.** Each non-empty section of the card is one
catalog title with the tag `card`: `Description`, `Personality`,
`Scenario`, `Greeting 1..n`, `Example dialogue`, and each entry of the
card's own lorebook by its name (tag `card-lore`). `article(title)` returns
that section's text. Without a chat this is the whole catalog, and the
Book step says so ("From the card alone: a short world, mostly places the
card names").

**What counts as fact.** The record of the chat is more than its
messages. The source reads all of it: the messages; the Journal cards
(`JournalMemories`, per chat per character, placed at the message they
were recorded against); the Growth rings (`GrowthRings`, one sentence
each, pinned or retired); and the chat's Objectives (`Objectives`, the
goal and its tasks, active or done, keyed by `stableGroupId` and chat
id). Journal and Growth ride with the chunk that holds their receipt, the
way `StoryChatMemory.chunkNotes` already places them; Objectives have no
message receipt and join the closing notes with the unplaced cards, as
"what the character was working toward". Together with the card these
are the facts; §3.3's Faithful or Creative choice says what the writer may
do beyond them.

**The chat is skimmed, not indexed.** The wiki scout reads the index and
never the articles, so chat chunks cannot be titles: "Chat part 3" says
nothing to a scout. The source runs a **Skim** pass first, one call per
chunk of fifty messages, cut exactly as the Distiller cuts them and with
the same `StoryChatMemory.chunkNotes` block for that stretch, asking for
the named things in it: places, factions, events, concepts, races, items,
people, one line each, with the kind, the aliases a chat would use, a
parent place when the text gives one ("the Tea Rooms in Bletchfield"), and
whether the stretch shows weather or a season. Names merge across chunks
by alias. The result is the catalog: each name a title, tagged with its
kind and `chat`, ranked by how many chunks mention it (so
`catalog.ranked` is true and the scout's "linked most" ordering applies).
`article(name)` returns the Skim line plus every message that names it or
an alias, oldest first, clipped the way wiki articles are clipped, with
the Journal cards, rings and Objectives that name it appended under the
same "confirmed by the chat's Journal" heading the Distiller uses.

The Skim's tool is `skim_chat` (names, kinds, aliases, parent, weather
flag), through the same tools gate as the scout; the wizard stays
tools-only. The Skim's progress lines go through the existing
`onProgress` channel ("Skimming the chat · part 3 of 8"), so both
progress panels show them with no new plumbing.

**The main character and the user are never titles.** The Skim prompt
lists both names as "already known, do not list", the source drops any
survivor, and the sign-off drops a card whose name matches either. They
inject through their own cards; a person card for them would be a second,
staler copy.

**The character's own lorebook is grounding, not output.** Its entries
are titles the scout may cite, and the write header carries their names
under "already in the character's book: do not rewrite these, chain to
them", so the new world adds to the book rather than duplicating it. A
Book step switch, *Copy the card's lorebook in* (default off), puts those
entries into the minted world unchanged for the author who wants one
portable file.

### 3.3 Everything after the catalog

Scout, shelf shape review, fill pass, write, entry review, places write,
climate, Review step and Mint run unchanged, with these source-aware
adjustments, each behind `source.kind`:

- **Depth.** Quick and Full only; Deep is not offered because there is no
  member catalog to walk. Card targets are read from the source: Quick
  "about 15 cards", Full "about 30 cards, reviewed" (constants beside
  `WorldWikiDepth`, pinned by `world_from_wiki_depth_test`). The shelf
  shape reviewer's "reads as a cast list" check accepts a world with one
  or two places when the source is a chat.
- **Where the story stands** is prefilled from the chat's end: the
  session summary (`chat.summary`, the same recap chat-to-story passes),
  editable, with the chip "from the chat's end".
- **Facts only or Creative** (a two-way choice on the Book step, not a
  switch; the story feature's faithful mode, worded for a world and made
  strict). Both read the same facts (§3.2: the messages, the Journal, the
  Growth rings, the Objectives, the card) and in both a sentence that
  contradicts them is a finding the entry reviewer sends back.
  **Facts only** (default when a chat is picked) adds no fact the record
  does not hold. The model still writes the sentences; it may not add to
  them. Concretely: the scout proposes only names the Skim found or the
  card states, and the fill pass does not run; every card carries the
  source lines it was written from and the write header says "restate
  what these lines say, in the world's voice; where they are silent, stop";
  the entry reviewer checks each sentence against those lines (not
  against what the model knows of the genre) and an unsupported sentence
  is a rewrite with the finding naming it; a card whose lines cannot carry
  three sentences is dropped with the verdict "nothing in the chat to
  write this from"; climate is written only from weather lines the Skim
  flagged, never guessed, and the Review says "no weather in the chat;
  climate left off" when the switch was on and none was found; Where the
  story stands is the chat's own summary unless the author edits it. The
  shelf is smaller and true, and a short chat makes it small (§3.5).
  **Creative** (default for Card only): the scout may propose cards the
  sources only hint at, shown on the Shelf with an `invented` chip and
  unsigned by default; the fill pass runs; the writer may fill the world
  in around the facts; the entry reviewer marks what it added so the
  Review step shows an `extrapolated` chip on those cards, with the
  invented part named in the verdict line; climate may be guessed from
  the card and is labelled so. Either way the author sees which is which
  before Mint, and the choice is remembered per character for the next
  run.
- **Climate** stays off by default. On, the climate call reads the Skim's
  weather lines when any chunk showed weather, else the Scenario, and the
  Review step's place row says "weather from the chat" or "guessed from
  the card".
- **The user's persona is written as `{{user}}`** in every entry, never by
  name, so an exported `.fpworld` or a Stoop WORLD card carries no persona
  name. The write header says so; a source test pins that a minted entry
  never contains the persona name (`StoryChatHistory` already resolves it
  for the Distiller). Slice 2 confirms the lorebook injector fills the
  macro in entry content as it does in keys (`lorebook_scanner.dart`
  already documents `{{user}}` keys); if it does not, that is a one-line
  fix in the injector, not a reason to write the name.
- **Provenance.** `World.sourceId = 'character:<stableGroupId>'`, with
  `/<sessionId>` appended when a chat was used. The library card shows a
  `from <character>` tag beside `model-made` where it applies; nothing is
  linked, so renaming or deleting the character leaves the world alone.

### 3.4 Budget

A 400-message chat is eight Skim calls, each a chunk plus its Journal
notes, sized by the wizard's own context like every other call. The scout
reads the Skim's index, not the chat, so it costs what a small wiki costs.
The writer reads per card only the lines that name it. Nothing reads the
whole chat twice.

### 3.5 Short chats and the floor

The Skim reads fifty messages a pass and a roleplay chat names roughly one
new place, person or thing every five to eight messages. Quick wants
about fifteen cards, Full about thirty. From that, three thresholds, kept
as named constants beside `kShortChatMessages` in
`story_chat_sources.dart` (estimates, like the story feature's own, and
pinned by a test so a retune is one edit):

| Constant | Messages | Turns | What the picker does |
|----------|----------|-------|----------------------|
| `kWorldChatMessagesFloor` | 40 | 20 | chip `too short to skim`; the row is still pickable; the line under the list says "Under 40 messages there is almost nothing to skim: Card only, or Creative, does better" |
| `kWorldChatMessagesShort` | 100 | 50 | chip `short chat`; "Fewer than 100 messages (about 50 turns). Facts only will give a thin shelf, likely under ten cards" |
| `kWorldChatMessagesForFull` | 200 | 100 | the Full tile's hint reads "Below 200 messages Full is mostly review passes over the same cards"; Quick is suggested |

Counts are messages, as the story picker counts them, and the copy says
turns in brackets. `worldChatLengthWarning(messages, mode, depth)` is the
one function that produces these lines, in the shape of
`chatLengthWarning`, and both surfaces call it. The warning never blocks:
a short chat with Facts only is a true, small world, which is a valid
thing to want.

## 4. Data and portability

No schema change. `sourceId` already exists. `.fpworld` and the Stoop
envelope are unchanged; a world from a character exports and posts like
any other. The relay payloads are additive (§5).

## 5. UI (desktop and web in the same slice, parity law)

**Worlds page.** The header gains **From Character** beside From Wiki, the
same outlined style, on the desktop (`world_management_header.dart`) and
the web (`WorldsPage.tsx`, route `/worlds/from-character`). The page
subtitle keeps its one line.

**The wizard.** The same page class with a `source` argument, the same
title bar, the same step strip (Setup, Book, Shelf, Write, Review), the
same nav. The title reads "World from Character" and the Book subtitle
"Scouting Yoruichi's chat · Quick · 32K".

**Setup** is unchanged: pick the model that writes it, the tools check,
Check now.

**Book** is four cards, 1 to 4 of 4, in the wiki's `WorldSectionCard`:

1. **The world** — World name, One-line premise, Where the story stands.
   Name and premise prefill from the card (`worldNames.first` or the
   Scenario's first clause; the premise from the Scenario) and stay
   editable; Where the story stands prefills from the chat's summary when
   a chat is picked, with the chip `from the chat's end`.
2. **The source** — a search field and the characters as `WorldPickTile`s
   (avatar, name, `N chats`), then, once one is picked, that character's
   chats as rows in the chat picker's shape (name, date, message count,
   `short chat` or `too short to skim` chip, §3.5) with **Card only** as
   the first row, and under the list the one warning line
   `worldChatLengthWarning` gives for the picked row, mode and depth. A
   character with no chats shows Card only and the line "No chats with
   Yoruichi yet. The card alone makes a short world."
3. **How deep** — Quick and Full tiles with their card counts and time
   hints for this source, and the Context for this wizard pills, as the
   wiki step has them.
4. **What to make** — first the **Facts only or Creative** pair as two
   `WorldPickTile`s across the card ("Nothing the chat, its Journal,
   Growth and Objectives, and the card do not say. The model writes the
   sentences; it adds no fact" against "The same facts, and the model may
   fill the world in; what it adds is marked"), then the
   Lorebooks and Climate switches as today and Copy the card's lorebook
   in, each with its one-line blurb.

Next reads **Skim chat** when a chat is picked and **Scout card** when it
is not; the hint under it says "one pass per 50 messages, then the scout".

**Shelf, Write, Review** are the wiki's steps. The progress panel's stage
strip gains a first chip, `1 · Skim`, only for this source. On Review,
each card's verdict line may add `extrapolated` (Stay with the chat off)
and a place row may say `weather from the chat`. "+ Add a card here" asks
for a name and, in place of a wiki page title, "what in the chat to read"
(blank reads the lines that name it). Mint World is the only save.

**Web.** `WorldFromWikiPage` takes the source from the route; the Book
step swaps card 2 for the character and chat pickers, fed by the existing
`/api/characters` and `/api/stories/chat-sources` (filtered to the picked
character client-side). Relay: the scout body gains
`source: {kind: 'character', characterId, sessionId?, faithful, copyCardLore}`
(absent means wiki, so an older client is unchanged); `status` gains
`sources: ['wiki', 'character']` and per-source `depthChoices`; progress
and done payloads are the ones that exist. Sweep route and a journey per
the web test rules.

**Dialog and copy rules** as everywhere: `showWarmDialog`, theme colours
only, no `{{char}}` or enum name rendered, 400 px and 1440 px.

The sketch: the desktop and phone artboards of "World from Character"
(private artifact, 2026-10-24): the Worlds page header, the Book step on
both surfaces, the progress card while skimming, the Review step and the
library card.

## 6. Delivery: four PRs in order, each shippable alone

| # | Slice | Depends on | Guard that goes red first |
|---|-------|-----------|---------------------------|
| 1 | `WorldSource` seam: interface, `WikiWorldSource`, engine and facade take the interface | — | none new; `world_from_wiki_test`, `world_review_loop_test`, `WorldFromWikiPage.tools.test.tsx` stay green unedited, which is the pin |
| 2 | `CharacterChatWorldSource` (card sections, Skim, article lookup, persona macro, main-character exclusion), Quick/Full counts, From Character on both Worlds pages, Book step card 2, relay `source`, provenance tag | 1 | new `test/services/world_from_wiki/world_from_character_source_test.dart`: card sections become titles, Skim tool payload decodes and merges by alias, `article` returns only lines naming the title with Journal notes appended, the main character and the user are never titles, a minted entry never carries the persona name, group sessions are not offered, `worldChatLengthWarning` gives the §3.5 line at 39, 99 and 199 messages and nothing at 200; `world_from_wiki_depth_test`: source card targets; `worlds_management_test`: From Character opens the wizard, picking a character lists its chats; web `WorldFromWikiPage.character.test.tsx`, sweep route, journey |
| 3 | Facts only or Creative: `invented` shelf chips, `extrapolated` verdicts, drop-for-no-source and no fill pass under Facts only, Objectives in the closing notes, Where the story stands from the chat's end, climate from weather lines, Copy the card's lorebook in | 2 | `world_review_loop_test`: an unsupported sentence is a rewrite under Facts only and a chip under Creative, a contradiction is a finding under both, the fill pass is not called under Facts only; source test: Objectives reach the closing notes, weather lines reach the climate call and no weather means climate off under Facts only, copied entries are byte-equal |
| 4 | Group chats as a source (several characters, each excluded from person cards, speaker names kept) | 2 | source test: a group session's speakers are all excluded; picker lists groups |

Slices 1 to 3 are the feature. Slice 4 is the path-complete debt
(1:1 ↔ group) named up front rather than discovered later; the picker in
slice 2 lists 1:1 sessions only and says why in one line.

Path-complete matrix: this feature writes no chat state. Generation,
Continue, regen, Journal, Growth, Pockets, RAG and the clock are untouched;
the minted world reaches a chat only through the existing Setting and Lore
slots, whose contracts `chat_places_primary_lore_test` already pins.
Desktop ↔ web in every slice.

## 7. Decisions taken

- One entry point: the Worlds page. Nothing inside a chat.
- A second source behind the one engine, not a second wizard.
- The chat is skimmed into an index before the scout; the scout never
  reads raw chat.
- The main character and the user get no person card.
- The card's lorebook is grounding; copying it in is an opt-in switch.
- Quick and Full only; smaller targets than a wiki.
- Facts only or Creative is a two-way choice; Facts only when a chat is
  picked, Creative for Card only; the same facts ground both, including
  the Journal, Growth rings and Objectives. Facts only adds no fact: no
  fill pass, no guessed climate, every sentence checked against its lines.
- The short-chat warning fires under 100 messages (about 50 turns), the
  too-short chip under 40, and Full is advised against under 200. It
  warns, never blocks.
- The persona is `{{user}}` in every entry.
- Provenance through `sourceId`; `linkedCharacterId` stays retired.
- 1:1 chats first; groups are slice 4, said in the picker.

## 8. Open questions for the maintainer

- Button wording: **From Character**, or **From a Chat** with the
  character picked inside? The doc assumes the former because the card
  alone is a valid source.
- Should a model-made (Scene Guest) character be offered as a source? The
  doc assumes yes; they are characters.
- Should the Skim also seed Living Time (a story clock start date from the
  chat's first day)? Out of scope here; worth its own line later.

## 9. Compatibility

Nothing changes for World from Wiki: the seam is a refactor pinned by the
unedited existing tests, the relay body without `source` means wiki, and
an older web client never sends one. A world minted from a character is a
root World with places, indistinguishable in the engine from a wiki world
except for its `sourceId` and the library tag. Nightly / Rawhide data
isolation is unaffected.
