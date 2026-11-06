# Reorderable chat sidebar — statement of work

Status: **proposed 2026-11-04, awaiting build.** The chat sidebar's section
order was fixed in code: a user could not move a section, a leaf, or a toggle.
This work makes every top-level sidebar section and every accordion leaf
reorderable by a grip handle, saves one global layout, adds a small visible
**Reset to default** pill at the top of the sidebar, and ships desktop + web in
one change. Companion to [path-complete-chat-work.md](path-complete-chat-work.md)
(the desktop ↔ web twin rule) and the sidebar's own layout tokens
(`lib/ui/chat_components/sidebar/sidebar_tokens.dart`).

## Overview

The chat sidebar has two layers today. The pinned chrome (`ChatRightSidebar`:
mood portrait, Main Settings popup, Group Settings button, participant roster)
sits above a scrolling body (`SidebarBody`, a plain `ListView`) whose order is
hard-coded: Director header → One-Shot Eval → Tool-Calling pill → Lite banner →
Author's Note → Wiki → Character State → Journal & Memory → Objectives → Story
Tools. Accordion *expansion* is already persisted globally in `UiSettings`
(`sidebar_group_expanded_<id>`), so an order list has a natural home beside it.

The web twin (`ChatInsight` + `ChatTools`) renders the same sections in its own
fixed order inside the insight column (desktop) and the insight drawer
(phone/portrait tablet). It has a different section vocabulary, so it gets its
own saved order.

This work adds drag-to-reorder to both surfaces, one global layout per surface,
a Reset pill, and no promotion of a leaf out of its accordion.

## Decisions (settled by the maintainer, 2026-11-04; do not re-open)

### Scope

- **Top-level sections and accordion leaves.** Every section in the scrolling
  body is movable, and every headed panel inside Story Tools and Journal &
  Memory is movable inside its own accordion.
- **Character State is split too** (maintainer follow-up, 2026-11-04,
  supersedes the one-block call): its portions — the realism-off note, the
  focused member's card, the bond bars, the fixation chip, the needs line +
  grid, ambitions, pockets, and the time strip — each carry a grip and move
  inside the accordion (ids `realism_off`, `member_card`, `bond_bars`,
  `fixation`, `needs`, `ambitions`, `pockets`, `time`). Fixation rides just
  after the bars it belongs to, but moves on its own (maintainer, same day).
  Gates travel with the leaf: the Needs grid still shows from the live
  `needsActive` gate, not the stored switch (Error Book 2026-10-08).
- **No promotion.** A leaf stays inside its accordion; Places cannot leave Story
  Tools to become its own top-level card.
- **Pinned chrome stays pinned.** The portrait, Main Settings, Group Settings
  and roster do not move among the sections.
- **One global layout.** The arrangement is one per surface, not per chat.
- **Explicit grip handle.** A drag-handle icon on each section and leaf; taps
  elsewhere still expand or toggle. (Error Book P44: a drag must not act until
  the movement is unmistakable; the press must still work as the click it was.)
- **Reset at the top.** A small but visible pill at the top of the sidebar
  opens a Yes/No confirmation (the order is global — losing it is lost for
  every chat) and only then restores the default order. (Maintainer
  follow-up, 2026-11-04.)
- **Wheel scrolls while a tab is in hand.** A reorderable list freezes its
  own scroll during a drag; the body wraps its list in a `Listener` that
  pumps wheel scrolls by hand while any grip is held, its own list or a
  nested accordion's alike (maintainer follow-up, 2026-11-04).
- **Desktop + web in one change.** Parity is mandatory unless the maintainer
  defers the web item in this conversation.

### The units and their ids

Top-level ids, in the shipped default order:

| id | widget | appears |
| --- | --- | --- |
| `director` | `DirectorPanel` | group or multi-speaker only |
| `one_shot_eval` | `OneShotEvalRow` | always |
| `tool_calling_pill` | `ToolCallingPill` | always |
| `lite_banner` | `_LiteNpcBanner` | focused lite guest only |
| `author_note` | `PorchAccordion('author_note')` | always |
| `wiki` | `WikiPanel` | always |
| `character_state` | `CharacterStateGroup` | 1:1 or group, not lite |
| `journal_memory` | `JournalMemoryGroup` | always |
| `objectives` | `PorchAccordion('objectives')` | 1:1 full chat, active only |
| `story_tools` | `StoryToolsGroup` | always |

Leaf ids, per accordion:

| container | id | widget |
| --- | --- | --- |
| `story_tools` | `chaos` | `ChaosPanel` |
| `story_tools` | `afk` | `AfkPanel` (1:1 only) |
| `story_tools` | `places` | `ChatPlacesPanel` |
| `story_tools` | `lorebook` | `LorebookSection` / `GroupLorebookSection` |
| `story_tools` | `chat_lorebook` | `ChatLorebookSection` |
| `journal_memory` | `summary` | `SummarySection` |
| `journal_memory` | `journal` | `JournalPanel` |
| `journal_memory` | `memory` | `MemoryPanel` |
| `journal_memory` | `growth` | `GrowthPanel` |
| `character_state` | `realism_off` | the Realism-off note (1:1, engine off) |
| `character_state` | `member_card` | the focused `GroupMemberCard` (group only) |
| `character_state` | `bond_bars` | `BondBars` |
| `character_state` | `fixation` | `FixationChip` (1:1, active fixation only) |
| `character_state` | `needs` | `NeedsLine` + `NeedsGrid` (live gate) |
| `character_state` | `ambitions` | `AmbitionsRow` |
| `character_state` | `pockets` | `PocketsRow` |
| `character_state` | `time` | `TimeStrip` + `PresenceWord` |

Web insight ids (its own vocabulary, its own saved order): `one_shot_eval`,
`tool_calling_pill`, `cast_chips`, `portrait`, `author_note`, `realism_stats`,
`chat_tools`, `places`, `lorebook`.

Web ChatTools ids (its own vocabulary, its own saved order): `realism_toggle`,
`needs_toggle`, `context_budget`, `wiki`, `memory`, `ambitions`, `pockets`,
`our_story`, `promises`, `belongings`, `chaos`, `objectives`, `recap`,
`scene_time`, `nsfw`, `group_settings`.

## Persistence

A new mixin file `lib/services/storage/settings/sidebar_layout.dart` holds the
layout, so `UiSettings` (already 497 lines, under the 500-line ratchet) gains
`with SettingsBase, LibraryViewPrefs, SidebarLayout` without growing.

Fields and keys:

| Surface | Field | Key |
| --- | --- | --- |
| Desktop top-level | `_sidebarOrder` | `sidebar_order` |
| Desktop leaves | `_sidebarLeafOrder` (container → list) | `sidebar_leaf_order_<container>` |
| Web insight | `_webSidebarOrder` | `web_sidebar_order` |
| Web ChatTools | `_webSidebarToolsOrder` | `web_sidebar_tools_order` |
| Layout lock (both) | `_sidebarLayoutLocked` | `sidebar_layout_locked` (absent = off) |

API: `sidebarOrderFor(visibleIds)` / `setSidebarOrder(list)`;
`sidebarLeafOrderFor(containerId, visibleIds)` / `setSidebarLeafOrder(...)`;
`webSidebarOrderFor(...)` / `setWebSidebarOrder(...)`;
`webSidebarToolsOrderFor(...)` / `setWebSidebarToolsOrder(...)`;
`sidebarLayoutLocked` / `setSidebarLayoutLocked(bool)`;
`resetSidebarLayout()` (clears every order key, restores defaults, notifies;
leaves the lock alone).

**Order resolution rule.** Stored ids are never dropped. Visible ids follow the
stored order; ids not in the stored list (new or conditional) append per the
default order. A section hidden right now (Objectives inactive, Lite banner
absent, Director absent) keeps its stored slot for when it reappears. A reorder
that happens while some sections are hidden must not corrupt the hidden ids'
positions.

Defaults match today's order: `[director, one_shot_eval, tool_calling_pill,
lite_banner, author_note, wiki, character_state, journal_memory, objectives,
story_tools]`; leaves `story_tools: [chaos, afk, places, lorebook,
chat_lorebook]`, `journal_memory: [summary, journal, memory, growth]`; web
insight and web tools per the tables above.

## Desktop top-level reorder

`SidebarBody` replaces its plain `ListView` with `ReorderableListView.builder`
(`buildDefaultDragHandles: false`), items keyed `ValueKey('sidebar-section-<id>')`,
`onReorderItem` → `ui.setSidebarOrder`. The visible-id set is computed from the
existing conditionals; the resolved order drives item order. Pinned chrome stays
pinned above the body.

## Desktop leaf reorder

`StoryToolsGroup` and `JournalMemoryGroup` replace their body `Column` with a
nested `ReorderableListView.builder` (`shrinkWrap` + `NeverScrollableScrollPhysics`,
inside the outer list), items keyed `ValueKey('sidebar-leaf-<id>')`,
`onReorderItem` → `ui.setSidebarLeafOrder(containerId, list)`. The leaf order is
resolved by the same rule. Character State keeps its own body order.

## The grip

One shared widget `SidebarReorderHandle` (`Icons.drag_handle`, 16px, tooltip
"Drag to reorder") sits as the **first element of each section's or leaf's
header row**:

- accordions → a new `dragHandle` slot on `PorchAccordion`, before the chevron,
  wrapped opaque so a grip tap never toggles expansion (the trick the trailing
  controls already use);
- plain cards → `OneShotEvalRow`, `ToolCallingPill`, `_LiteNpcBanner`,
  `WikiPanel`, `DirectorPanel` header rows;
- leaves → a new `dragHandle` slot on the shared `SidebarSubHeader`, which Chaos,
  AFK, Places, Lorebook, Chat Lorebook, Summary, Journal, Memory and Growth
  already use.

The grip consumes header width. `SidebarTokens` says 230 is the smallest pane
where "Character State" holds two whole-word lines with switch AND gear; the
grip adds ~20px. Verify at 230/400/1440 and either shrink header gaps or raise
`SidebarTokens.minWidth` (touching the width tests, under the maintainer's
label).

## The Reset pill

A compact pill at the very top of the sidebar (above the portrait on desktop;
above the insight children on web) reads **Reset to default** and calls
`ui.resetSidebarLayout()`. It is pinned chrome, not a reorderable unit. On web
it POSTs `/api/settings { resetSidebarLayout: true }`.

## The layout lock (2026-11-06)

A second pill sits beside **Reset to default** and reads **Lock layout** /
**Layout locked**. Toggled on, it sets `sidebarLayoutLocked` and no grip on
either surface starts a drag: every top-level section and every nested
accordion leaf draws a dimmed lock icon instead of its grip. The order itself
is untouched — only the drag start disappears — and the switch is one global
preference like the order.

- Desktop: `SidebarReorderLock` (an `InheritedWidget` in `sidebar_reorder.dart`)
  wraps the body; `SidebarReorderHandle` reads it and renders an inert
  `Icons.lock_outline`.
- Web: `SidebarGrip` takes `locked` and renders an inert lock; `useReorderDrag`
  also refuses to start, belt-and-braces.
- **Reset stays available while locked** and does **not** clear the lock:
  resetting the order must not silently re-open a layout the user asked to
  protect. The lock is a separate key (`sidebar_layout_locked`), absent when
  off, so a fresh install and the default are unlocked.
- The pills wrap to a second line on a narrow sidebar rather than clipping
  either control (Error Book: never fit a toolbar by hiding controls).

## Web twin and transport

The host facade carries the layout to the PWA:

- `settings_snapshot.dart` exposes `sidebarOrder`, `sidebarLeafOrder`,
  `webSidebarOrder`, `webSidebarToolsOrder` (additive; an older PWA ignores them).
- `settings_writer.dart` writes them and handles `resetSidebarLayout`.
- `web_live_relays.dart` carries the order keys in the `settings_changed` event
  so an open page repaints at once.

`ChatInsight.tsx` makes its children reorderable (pointer-drag grip, reorder live
as the pointer crosses a neighbour's **midpoint**, the repo's `InterviewCard.tsx`
pattern), reads the order from `/api/settings`, POSTs on reorder, and renders the
Reset pill at the top. `ChatTools.tsx` makes its sections reorderable the same
way. A shared `web_ui/src/components/sidebarReorder.ts` holds the pointer-drag
helper, the order resolution and the persistence calls.

## Tests

- **Desktop** `test/ui/chat_components/sidebar_reorder_test.dart`: grip drag
  reorders a top-level section; order survives a remount (mocked prefs); Reset
  restores the default; a hidden conditional section does not corrupt the stored
  order; a nested leaf reorder works. No stub network.
- **Desktop lock** `test/ui/chat_components/sidebar_lock_test.dart`: locking
  swaps every grip for the inert lock, a drag moves nothing, Reset still
  restores the default while locked (and does not unlock), unlocking brings the
  grips back.
- **Web** `ChatInsight.reorder.test.tsx` + `ChatTools.reorder.test.tsx`: pointer
  drag reorders and POSTs the order; Reset POSTs the reset. (P40: derive the
  expected index from the product's midpoint rule and write the numbers used.)
- **Web lock** `SidebarLock.reorder.test.tsx`: the lock POSTs, every grip turns
  inert, a drag moves nothing, Reset still POSTs while locked, unlocking
  restores the grips.
- **Rendering**: the grip renders on each section and leaf; taps elsewhere still
  expand/toggle; the Reset pill is visible at the top; the header holds at 230.
- **Goldens**: the sidebar goldens drift when grips are added → regenerate with
  the maintainer's `update-goldens` label. If the grip forces a min-width change,
  the sidebar width/multires tests also need `approved-test-change`.

## Files

Verified against the tree on 2026-11-04. `ui_settings.dart` (497) and
`sidebar_body.dart` (394) stay under the 500-line cap by putting the layout in
the new mixin and the grip/order helper in a new leaf; no new `part` files.

| Stage | New | Changed |
| --- | --- | --- |
| Persistence | `lib/services/storage/settings/sidebar_layout.dart` (fields, defaults, load, order resolution, setters, reset) | `lib/services/storage/settings/ui_settings.dart` (`with SidebarLayout`, `loadSidebarLayout()` in `load()`) |
| Desktop top-level | `lib/ui/chat_components/sidebar/sidebar_reorder.dart` (`SidebarReorderHandle`, visible-id ordering) | `sidebar_body.dart` (ReorderableListView, order wiring, grip on Lite banner + Director header), `porch_accordion.dart` (`dragHandle` slot), `one_shot_eval_row.dart`, `tool_calling_pill.dart`, `wiki_panel.dart`, `lib/ui/chat_components/widgets/director_panel.dart` (grips), `lib/ui/pages/chat_page.sidebar.dart` (Reset pill at the top) |
| Desktop leaves | — | `story_tools/story_tools_group.dart` (nested ReorderableListView + order wiring), `story_tools/chaos_panel.dart`, `story_tools/afk_panel.dart`, `story_tools/chat_places_panel.dart`, `story_tools/lorebook_panel.dart`, `story_tools/lorebook_chat_book.dart`, `journal_memory/journal_memory_group.dart`, `journal_memory/summary_section.dart`, `journal_memory/journal_panel.dart`, `journal_memory/memory_panel.dart`, `journal_memory/growth_panel.dart`, `sidebar_tokens.dart` (`dragHandle` slot on `SidebarSubHeader`) |
| Host transport | — | `lib/services/web/facade/settings/settings_snapshot.dart`, `lib/services/web/facade/settings/settings_writer.dart`, `lib/services/web/host/web_live_relays.dart` |
| Web | `web_ui/src/components/sidebarReorder.ts` (pointer-drag, order resolution, persistence) | `web_ui/src/components/ChatInsight.tsx` (reorderable children + Reset pill), `web_ui/src/components/ChatTools.tsx` (reorderable sections), `web_ui/src/styles/chat.css` (grip + pill styles); then `npm run build` |
| Tests | `test/ui/chat_components/sidebar_reorder_test.dart`, `web_ui/src/components/ChatInsight.reorder.test.tsx`, `web_ui/src/components/ChatTools.reorder.test.tsx` | `test/golden/widget/_goldens/sidebar/*.png` (regenerated), `test/ui/chat_components/sidebar_multires_layout_test.dart`, `test/ui/chat_components/expandable_sidebar_text_test.dart`, `test/ui/chat_components/sidebar_width_env_test.dart`, `integration_test/sidebar_sweep_test.dart` (only if the grip forces a min-width change) |
| Docs | `docs/design/sidebar-reorder.md` (this SOW) | — |

Left alone on purpose: the pinned chrome (portrait, Main Settings, Group
Settings, roster); Character State's internal dashboard; `sidebar_group_expanded_*`
(the expansion keys stay as they are); the `settings-parity-manifest.json` (the
Reset pill is a sidebar control, not a Settings-page control).

## Labels the maintainer applies

- `update-goldens` — the sidebar pixel baselines regenerate (grips + pill).
- `approved-test-change` — only if the grip forces a min-width change and the
  width/multires tests are edited; new test files never need it.

## Risks

- **P44** — the grip must not steal the expand tap; drag acts only after
  unmistakable movement. Explicit handle + opaque wrapper.
- **P26** — the web reads the order asynchronously; reads must be ticketed and
  overtaken ones dropped.
- **P40** — drag tests derive the expected index from the product's midpoint rule.
- **Header width at 230** — the grip consumes ~20px; verify and adjust gaps or
  `minWidth`.
- **File-size ratchet** — the mixin and the helper keep both near-cap files flat.
- **Parity** — web twin in the same change.
- **Error Book** — read each file's folder entries before editing; any error this
  work causes gets an entry the same sitting, then the indexes rebuilt.

## Status

- 2026-11-04: SOW written from the maintainer's five calls (scope, global,
  parity, reset, grip) plus two follow-ups (Reset at the top as a pill;
  Character State stays one block). Awaiting build in a separate worktree.
- 2026-11-06: built; layout lock added beside Reset (maintainer request):
  one global switch, inert grips on both surfaces, Reset still works while
  locked and leaves the lock on.
