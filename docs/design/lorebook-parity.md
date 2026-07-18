# Lorebook / World Info Parity — Deep Dive & Roadmap

*Exploration date: 2026-07-04. No code changed yet — this is the gap analysis and plan.
Benchmark: SillyTavern (`release` branch, verified against `world-info.js` / `macros.js` source,
July 2026), Chub.ai (which uses the ST/V2-card interchange format), Character Card V2/V3 specs,
plus the foreign formats ST auto-detects (NovelAI, AgnAI, RisuAI).*

---

## 1. Where FPAI stands today

A lorebook entry in FPAI has **6 meaningful fields**: `name`, `key` (one comma-separated
string), `content`, `enabled`, `constant`, `stickyDepth`. SillyTavern's entry has **~40**.

What we do have and that works:

- Tolerant import of ST / Chub / FPAI JSON shapes (`entries` as list or as `{"0": {...}}` map,
  `disable` vs `enabled`, `comment` vs `name`) — `lib/models/lorebook.dart`.
- Whole-word, case-insensitive keyword matching with `*` wildcards — `lib/services/chat/lorebook_scanner.dart`.
- Sticky-turns persistence (`stickyDepth`/`remainingDepth`), constant entries, AI-response scanning
  (the AI's own reply can trigger lore for the next turn), trigger-state reset hygiene.
- A real macro engine (`lib/services/macro_resolver.dart`) with `{{user}}`, `{{char}}`,
  `{{random}}`, `{{pick}}` (deterministic seeding), `{{roll}}`, time/date macros, `{{//comments}}`,
  `\{{` escaping — **and lorebook content IS passed through it at injection time**
  (`chat_service_generation.dart:424`).
- Scope levels: per-character inline lorebook, attachable Worlds, group lorebook + group worlds +
  `inheritCharacterLorebooks` flag. Green/blue/red activation dots in the sidebar. Web UI parity
  for worlds CRUD/import/export.
- V2 `character_book` is read from imported cards and written back on export.
- Solid test coverage of what exists (~80 tests across model/scanner/injection/dialog/web).

**The storage is an opaque JSON blob** (`Characters.lorebook`, `Worlds.lorebook`,
`Groups.groupLorebook` are JSON text columns). This is great news for parity work: expanding the
entry model is **additive JSON, zero Drift migrations, zero Character Card Forge risk**.

---

## 2. Bugs and silent data corruption happening TODAY on import

These are not "missing features" — they actively make imported ST/Chub content behave wrongly.

| # | Problem | Where | Effect on users |
|---|---------|-------|-----------------|
| B1 | **Secondary keys flattened into primary keys.** ST's `keysecondary` + `selectiveLogic` (AND ANY / AND ALL / NOT ANY / NOT ALL) is destroyed: secondaries are appended to the primary OR-list. | `lorebook.dart` fromJson (lines 79-85) | An entry meant to fire only on "dragon" AND "cave" now fires on "cave" alone. Every selective entry in every imported book over-triggers. |
| B2 | **`insertion_order` misread as sticky depth.** ST's `order` (priority, commonly 100+) is coerced into `stickyDepth`. | `lorebook.dart` lines 110-119 | An entry with order 100 stays active for 100 turns after one trigger — effectively constant. Imported books flood the context. Same coercion mangles `depth` and ST's `sticky` timer. |
| B3 | **Probability ignored.** ST `probability`/`useProbability` dropped. | fromJson | 25%-chance flavor entries fire 100% of the time. |
| B4 | **Regex keys never match.** ST keys like `/dragons?/i` are matched as literal text (`RegExp.escape`d). | `lorebook_scanner.dart` `_matchKeyword` | Increasingly common in modern Chub books; those entries are dead on arrival. |
| B5 | **`{{random:a,b,c}}` leaks raw into the prompt.** Our macro regex only accepts the `::` separator; the single-colon + comma form (the most common form on Chub) fails to parse entirely and passes through as literal text. Same for `{{roll:d6}}` and `{{roll:6}}` shorthands (regex demands `NdM`). | `macro_resolver.dart` `_macroPattern`, `_rollPattern` | The model sees `{{random:sunny,rainy}}` verbatim. Verified: tests only cover the `::` form. |
| B6 | **Export is a one-way door.** `toCharacterBook()` emits hardcoded constants (`priority: 10`, `selective: false`, `secondary_keys: []`, `position: 'before_char'`, `scan_depth: 4`, `token_budget: 500`). Since dropped fields were never stored, importing an ST book into FPAI and re-exporting **permanently destroys** all behavioral metadata. | `lorebook.dart` lines 215-251 | Users who curate in FPAI can't share back to ST/Chub without loss; imported books can't round-trip. |
| B7 | **CJK keys can't match.** `\b` word boundaries don't work against CJK text; ST uses `(?:^|\W)key(?:$|\W)` for single words and substring for multi-word keys, plus a whole-word toggle (docs explicitly warn to disable it for CJK). We have no toggle and always use `\b`. | `_matchKeyword` | Japanese/Chinese/Korean lorebooks silently never trigger. |
| B8 | **Wildcard keys drop word boundaries entirely** — `pot*` matches "despot" (substring anywhere). Minor, but surprising. | `_matchKeyword` | Over-triggering on wildcard keys. |

---

## 3. Feature gaps vs SillyTavern (the parity checklist)

### 3.1 Entry-level fields not modeled anywhere (model, DB, editor, runtime)

ST field (JSON key) → what it does:

- `keysecondary` + `selective` + `selectiveLogic` (0=AND ANY, 1=NOT ALL, 2=NOT ANY, 3=AND ALL) — conditional triggering.
- `order` (default 100, sorted descending) — insertion priority & budget-drop order.
- `position` (0=before char, 1=after char, 2=AN top, 3=AN bottom, 4=@depth, 5=examples top, 6=examples bottom, 7=outlet) + `depth` (default 4) + `role` (system/user/assistant, @depth only).
- `probability` (default 100) + `useProbability` — trigger %; failed rolls remembered per scan; sticky-active entries skip the roll.
- `group` (comma-separated = multi-group) + `groupOverride` (highest order wins) + `groupWeight` (weighted random) + `useGroupScoring` (3-state) — inclusion groups: only one member of a group activates.
- `sticky` / `cooldown` / `delay` — timed effects in *message counts*, state in chat metadata (`{hash, start, end, protected}`): sticky force-activates + skips rolls + wins groups; cooldown blocks reactivation (starts `protected` when a sticky ends); delay suppresses until chat length ≥ N.
- `scanDepth` (per-entry override, 0 = don't scan chat), `caseSensitive` (3-state), `matchWholeWords` (3-state).
- `excludeRecursion` / `preventRecursion` / `delayUntilRecursion` (numeric levels; `true`≡1) — recursion controls.
- `ignoreBudget` — inserts even after budget overflow.
- `vectorized` — entry only activates via embedding similarity (we HAVE an embedding sidecar — natural FPAI fit).
- `matchPersonaDescription` / `matchCharacterDescription` / `matchCharacterPersonality` / `matchCharacterDepthPrompt` / `matchScenario` / `matchCreatorNotes` — extra scan sources.
- `automationId`, `triggers` (generation-type filter: normal/continue/impersonate/swipe/regenerate/quiet), `characterFilter` ({isExclude, names[], tags[]}), `displayIndex` (editor drag order), `uid`, `addMemo`.

### 3.2 Book-level / global settings not modeled

- Scan depth window (ST global default 2 messages; we scan exactly 1 message string).
- Context % budget (default 25%) + absolute token cap; overflow alert. We have no lore budget at all.
- Recursive scanning (activated entries' content re-scanned to trigger more entries; max recursion steps; min activations + depth-extension sweep).
- Case-sensitive / whole-word global defaults; include-names in scan buffer (`Name: text`).
- Insertion strategy (character-first / global-first / evenly), and ST's fixed ordering: chat book → persona book → char+global by strategy, each sorted by descending order. We collect into an **unordered Set deduped by exact content**.
- Book-level `scan_depth` / `token_budget` / `recursive_scanning` from V2 `character_book` (read by nothing today).

### 3.3 Interchange formats we don't handle

- **ST card extensions mapping** (the de-facto standard Chub also uses): everything beyond V2 rides `entry.extensions.*` with exact keys (`position` numeric, `probability`, `useProbability` (camel!), `selectiveLogic` (camel!), `exclude_recursion`, `prevent_recursion`, `delay_until_recursion`, `group`, `group_override`, `group_weight`, `scan_depth`, `case_sensitive`, `match_whole_words`, `use_group_scoring`, `automation_id`, `role`, `vectorized`, `sticky`, `cooldown`, `delay`, `match_*` flags, `triggers`, `ignore_budget`, `display_index`, `outlet_name`). We must read AND write these.
- **V3 cards** (`spec: 'chara_card_v3'`) and standalone `{spec: 'lorebook_v3', data: …}`: adds `use_regex` (required bool), string-or-number ids, and content **decorators** (`@@activate`, `@@dont_activate`, `@@depth N`, `@@role`, `@@scan_depth N`, `@@activate_only_after N`, `@@activate_only_every N`, fallback `@@@`…). ST implements only `@@activate`/`@@dont_activate` but strips recognized decorator lines — we render them as visible garbage today.
- **Foreign format detection markers** (how ST auto-detects on import):
  - NovelAI: `lorebookVersion` present → `entries[].keys/.text/.displayName/.enabled/.contextConfig.budgetPriority→order`.
  - AgnAI: `kind === 'memory'` → `keywords/.name/.entry/.weight→order/.enabled`.
  - RisuAI: `type === 'risu'` → `data[].key` (comma string)/`.secondkey`/`.alwaysActive→constant`/`.insertorder`/`.activationPercent→probability`.
  - Else, anything with an `entries` object = native ST world info.
- V2 spec compliance notes: `extensions` must be **preserved** round-trip (we discard); char book SHOULD take precedence over world book; `insertion_order` lower = higher in prompt.

### 3.4 Macro gaps (ST evaluates macros in WI keys AND content, every generation)

Have: `user, char, newline, space, noop, random(:: only), pick(:: only), roll(NdM only), time, date, weekday, isotime, isodate, {{//}}, \{{ escape`, legacy `<user>/<char>`.

Missing / broken, in rough order of real-world frequency in Chub/ST content:

1. **Single-colon + comma-list forms**: `{{random:a,b,c}}`, `{{pick:a,b}}` (with `\,` escape), `{{roll:d6}}`, `{{roll:6}}` (digits → `1dN`), `{{roll d20}}` (space form). ST accepts `:` and `::` everywhere.
2. Macro substitution in **keys** before matching (we only substitute content).
3. Variables: `{{setvar::k::v}}`, `{{getvar::k}}`, `{{addvar}}`, `{{incvar}}`, `{{decvar}}` (+ global twins) — per-chat state, big in interactive lorebooks/RPG cards.
4. Chat context: `{{lastMessage}}`, `{{lastUserMessage}}`, `{{lastCharMessage}}`, `{{idle_duration}}`/`{{idleDuration}}`, `{{input}}`.
5. Time extras: `{{datetimeformat::FMT}}`, `{{time::UTC±X}}`, `{{timeDiff::a::b}}`.
6. Utility: `{{trim}}`, `{{reverse::text}}`, `{{banned::word}}`; group macros `{{group}}`, `{{charIfNotGroup}}`, `{{notChar}}`, `{{groupNotMuted}}`; card field macros (`{{description}}`, `{{personality}}`, `{{scenario}}`, `{{persona}}`, `{{mesExamples}}`, `{{charVersion}}`…); `{{original}}`.
7. New ST macro engine niceties (nesting `{{getvar::{{char}}_mood}}`, `{{if}}/{{else}}/{{/if}}`, `\{\{escaped\}\}` alt escape) — lower priority.
8. `{{pick}}` seeding: ours (chatId+charId+section+counter) is stable but diverges from ST's (chat hash + content hash + offset). Acceptable difference; document it.

---

## 4. UX / flow weak points (independent of the engine)

1. **No unified import flow.** "Import World JSON" on the World page dumps everything into a
   global World; there is no "import this lorebook and attach it to character X" path. Attaching
   requires separately opening the character editor → Worlds tab → checkbox list.
2. **Dual-storage confusion on character import.** An imported card's book is stored inline on
   the character AND copied into an auto-created World ("X's world lore", kept in sync on edit).
   Two sources of truth; only exact-string content dedup prevents double injection.
3. **Worlds are keyed by unique name** and attached by name (`worldNames`). Renaming a world
   silently breaks attachments. (`Worlds.id` UUID exists but isn't used for linkage.)
4. **No per-chat lorebook** and no persona lorebook (ST has both; chat book scans first).
5. **Editor exposes 6 fields** with no room to grow — needs a Simple/Advanced split.
6. **Activation surface**: red dot for "enabled but not currently triggered" reads as an error
   state; ST uses 🔵 constant / 🟢 keyed / 🔗 vectorized. No sticky/cooldown counters, no
   "what would trigger right now" dry-run preview, no budget/overflow feedback, no search within
   a book, no drag ordering, no duplicate-entry / move-to-book actions.
7. **Web UI** mirrors the same 6 fields (`LoreEntriesEditor.tsx`) — any model expansion needs the
   web editor + `lorebook_json.dart` bridge updated in the same phase.

---

## 5. Proposed roadmap

### Phase 1 — Fidelity foundation (store everything, break nothing)
- Expand `LorebookEntry` to the full ST field set with ST-compatible defaults, plus a
  preserved `extensions` map for unknown fields (V2 spec compliance + future-proofing).
  JSON-blob storage ⇒ no DB migration.
- Rewrite import: separate secondary keys + selectiveLogic; `order` as order (kill the
  stickyDepth coercion — map legacy FPAI `sticky_depth` explicitly); position/depth/role;
  probability; case/whole-word; recursion flags; timed effects; groups; `use_regex`; read the
  ST `extensions.*` card mapping; strip known decorators; detect NAI/AgnAI/Risu/lorebook_v3
  by their markers.
- Rewrite export: native ST world-info JSON (entries keyed by uid) and faithful
  `character_book` + `extensions.*` mapping. Round-trip test: ST JSON → FPAI → ST JSON must be
  semantically identical.
- Migration shim for existing FPAI books: current `stickyDepth` semantics preserved for
  already-created entries (map to ST `sticky` timer or keep as legacy field honored by the engine).

### Phase 2 — Matching & injection engine parity ✅ SHIPPED 2026-07-05
*(Everything below is live: shared enumerator + cached group book — fixing the
latent bug where group-book keyed entries could never trigger — scan windows
with book/entry overrides, recursion with prevent/exclude/delay levels,
positions incl. @depth splice into history, per-bucket ordering, token budget
with per-book caps + ignoreBudget + overflow plumbing (`lastLoreOverflow`),
inclusion groups with deterministic seeded winners, and sticky/cooldown/delay
timed effects persisted per-chat in the session's groupRealismState blob.
Deliberate deviations: global scan depth defaults to 1 (FPAI cadence; setting
exists), @depth `role` carried but not rendered in the text transcript, and
vectorized entries deferred. New engine files: chat/lorebook_collection.dart,
chat/lorebook_injector.dart, chat/lorebook_timed_effects.dart,
storage/settings/lorebook_settings.dart.)*
- Scan buffer over last N messages (global scan depth + per-entry override, include-names).
- Secondary-key logic (all 4 modes), regex keys (`/…/flags` detection identical to ST),
  macro substitution of keys, per-entry case/whole-word (ST's `\W` boundary + substring for
  multi-word — also fixes CJK), probability rolls with per-scan failure memory.
- Ordering by descending `order` within position blocks; insertion positions: before/after
  char defs, @depth with role (we already build chat-style messages), AN top/bottom.
- Token budget (% of context + cap + `ignoreBudget` + overflow surfacing).
- Recursion (prevent/exclude/delay levels, max steps), then min-activations sweep.
- Timed effects (sticky/cooldown/delay in message counts, state in session metadata,
  ST interaction rules: sticky skips rolls/wins groups; cooldown starts protected after sticky).
- Inclusion groups (override → scoring → weighted random).
- Optional FPAI flex: `vectorized` entries via our existing embedding sidecar (feature ST needs
  an extension for — a genuine differentiator, with graceful no-RAG fallback).
- **Parity discipline**: identical behavior 1:1 vs group (scanner already runs per the
  character-list callback; keep it that way), and the sidebar/web facade read the same state.

### Phase 3 — Macro parity ✅ SHIPPED 2026-07-05
*(Live: chat variables {{setvar/getvar/addvar/incvar/decvar}} + global twins
(locals persisted per chat in the session blob's `macroVars` key, globals in
prefs), {{lastMessage}}/{{lastUserMessage}}/{{lastCharMessage}},
{{idle_duration}} (in-memory clock), card-field macros
({{description}}/{{personality}}/{{scenario}}/{{persona}}), group roster
macros ({{group}}/{{groupNotMuted}}/{{notChar}}/{{charIfNotGroup}}),
{{time::UTC±N}} + legacy {{time_UTC±N}}, {{datetimeformat}} (moment→ICU token
map), {{timeDiff}}, {{trim}}, {{reverse}}, {{banned}} (stripped — sampler-list
wiring deferred), and macro substitution inside trigger KEYS. Unavailable
context → pass-through, never silent blanks. Deliberately out: {{input}},
{{original}}, {{mesExamples}}, nesting/{{if}} (ST's new engine), {{outlet}}.)*
- Accept `:` and `::` separators + comma lists + `\,` escapes; roll shorthands.
- Add: setvar/getvar/addvar/incvar/decvar (per-chat, persisted in session), lastMessage family,
  idle_duration, datetimeformat/timeDiff, trim, group macros, card-field macros.
- Substitute macros in keys pre-match. Keep unknown-macro passthrough.

### Phase 4 — UX overhaul ✅ SHIPPED 2026-07-05
*(Live: Simple/Advanced entry editor (ONE editor everywhere — fixed two
metadata-stripping edit paths + the group-settings tab that never saved),
Import Lorebook wizard (format detection, review, four destinations incl.
the new per-chat book), per-chat lorebook (session blob, chat-first scan
order), no more auto-created "X's world lore" duplicates, rename-safe worlds
(row updated by id + attachments follow), sidebar upgrades (gray idle dots,
timer pills, token meter, would-trigger preview, This Chat section), web
editor chance+placement. Deferred: vectorized entries, web Advanced grid,
optional cleanup prompt for legacy auto-created worlds. Golden note:
sidebar/lorebook.* pngs need CI regen.)*
- **One import entry point** ("Import Lorebook") that detects the format, shows a preview
  (entry count, features used, sample entries, anything unsupported), then asks the destination:
  standalone World, attach to character(s), attach to group, or this chat only.
- **Entry editor Simple/Advanced**: Simple keeps today's friendly fields + probability +
  position preset; Advanced exposes the full grid with "Use global" 3-states.
- **Per-chat lorebook** (and consider persona book later).
- Kill the dual-storage on card import: import inline book only, and offer "also publish as a
  shared World" as an explicit action (deprecating the auto-"X's world lore" copies — offer
  cleanup per CLAUDE.md's redundant-feature rule).
- Attach worlds by UUID instead of name (additive: keep name fallback for old data).
- Activation UI: blue/green/gray dots (drop red-as-inactive), sticky/cooldown countdown badges,
  live "would trigger" preview against the current draft message, per-generation lore token
  meter + overflow toast, search/sort/drag-order/duplicate/move-to-book in the editor.
- Web UI editor updated in the same phase (`LoreEntriesEditor.tsx`, `lorebook_json.dart`).

### Suggested sequencing note
Phase 1 + the B5 macro-separator fix are the highest-value, lowest-risk start: they stop the
data destruction and the raw-macro leakage immediately, even before the engine learns to *use*
the new fields. Phases 2–4 can then land feature-by-feature without another storage change.

---

## 6. Reference material

- ST source snapshots saved during research (world-info.js, macros.js, V2/V3 specs) under the
  session scratchpad `st-research/` — re-fetch from the ST `release` branch when implementing.
- Key FPAI files: `lib/models/lorebook.dart`, `lib/models/world.dart`,
  `lib/services/chat/lorebook_scanner.dart`, `lib/services/chat/chat_service_generation.dart`
  (lines ~140-200 assembly, ~424 macro pass, ~1218-1239 sticky decrement),
  `lib/services/macro_resolver.dart`, `lib/services/world_repository.dart`,
  `lib/services/v2_card_service.dart` (~218), `lib/services/character_repository.dart`
  (~596 auto-world), `lib/ui/dialogs/lorebook_entry_dialog.dart`,
  `lib/ui/pages/world_management_page.dart`,
  `lib/ui/chat_components/sidebar/story_tools/lorebook_panel.dart`,
  `web_ui/src/components/LoreEntriesEditor.tsx`, `lib/services/web/util/lorebook_json.dart`.
