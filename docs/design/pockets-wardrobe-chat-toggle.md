# Per-chat Pockets & Wardrobe toggle — statement of work

Status: **proposed 2026-11-04, maintainer decisions D1–D3 resolved (see
bottom); awaiting build.** Pockets & Wardrobe is today a global Porch Life
switch ANDed with a per-**character** card flag; there is no per-chat
control. This work adds the switch where users actually steer a chat: a
per-chat switch in **1:1** (like Realism/Needs) and a **per-member switch in
groups**, each gated by a Yes/No confirmation when toggled **off** (no
catch-up mechanic exists, so the user must be told the inventory freezes).
The character-editor switch is demoted from a runtime kill-switch to a
**default for new chats**, groups gain a group-level new-chat default plus a
per-member default, and **no pockets/wardrobe model call runs while a
member's switch is off**. Companion to
[path-complete-chat-work.md](path-complete-chat-work.md) (the desktop ↔ web
twin rule) and the reorderable sidebar ([sidebar-reorder.md](sidebar-reorder.md)
— `pockets` is a draggable leaf of `character_state` as of #706).

## Overview

1:1 chats:

1. **Per-chat switch** next to the Realism/Needs switches, persisted per
   session. Toggling **off** opens the confirmation first; only **Yes**
   flips it. The record (worn/carrying/set-aside — "wardrobe" *is* the
   `worn` list; there is no separate wardrobe store) is **retained, never
   erased**, and **no pockets model call runs while off** — neither the
   standalone `report_inventory` eval, nor its fused reply-facts slice, nor
   the per-turn prompt injection.

Group chats (maintainer ruling 2026-11-04):

2. **Per-member, all the way down.** Each member carries their own pockets
   switch, toggleable **at will mid-chat** from that member's card/leaf in
   the sidebar — flipping Mara's off halfway through the chat works exactly
   like the 1:1 toggle, same warning popup (with the member's name in the
   copy).
3. **Two defaults decide the starting state of a new group chat**, one per
   level, ANDed: the **group's new-chat default** (a switch in Group
   Settings' new-chats surface, next to Realism/Afterglow's) AND each
   **member's default** (the character's `pockets_enabled` card flag,
   editable per member on their settings card, following the Afterglow
   member-row precedent). Worked example: group default ON, Ben's default
   OFF ⇒ at chat start Mara and Shawn are on, Ben is off — and the user can
   still flip Ben on (or Mara off) later in the chat.
4. The character-editor switch **stops being a runtime kill-switch** and
   becomes the default seed for new chats — the exact pattern
   `needsSimChoice` + `seedNeedsSim` already follow.

## The contract

- **Off hides, never erases** — the established pockets law
  (`pockets_ledger.dart:75-79`, "HIDES≠erase"; `session_saver.dart:227-234`,
  `session_scalars.dart:250-258` already persist/restore the record outside
  any gate). The dialog promises retention, so the load/save wires keep
  writing records unconditionally, off members included.
- **No catch-up.** Re-enabling must NOT fire `seedPocketsFromCards()` over a
  non-empty retained record and must NOT run a retroactive scan (contrast
  `setRealismEnabled`'s `onRealismStarted()`, `controls_door.dart:233`).
  Exception: enabling a track whose record is empty (seeded off from a
  default) seeds that card's starting inventory once — mirroring
  `setNeedsSimEnabled`'s first-enable seeding (`controls_door.dart:264-290`).
  Applies per member in groups.
- **Silence while off.** Zero pockets model calls, zero pockets prompt
  injection, zero hand-edit acceptance for that scope (the whole chat in
  1:1; just that member in a group — other members' tracks keep running).
  Historical receipt chips on old bubbles stay — they are history.
- **The live gate covers what runs AND what shows** (Error Book
  2026-10-08: `2026-10-08-needs-bars-shown-from-stored-switch`). Every
  display read of the old flag moves in the same change; grep `lib/ui`,
  `lib/services/web/facade`, `web_ui/src` for it.

## Confirmation copy

Shown on toggle-**off only** (toggle-on is instant).

1:1:

> **Turn off Pockets & Wardrobe?**
> There is no catch-up mechanic implemented. If you turn this off, your
> character's current inventory and wardrobe will be retained but no longer
> tracked — changes in the chat will not be reflected when you turn it back
> on. Are you sure you want to do this?
>
> **[ Yes, turn off ]**  **[ No, keep on ]**

Group (same popup, member named — maintainer: "same warning pop up in groups
as 1:1"):

> **Turn off Pockets & Wardrobe for Ben?**
> There is no catch-up mechanic implemented. If you turn this off, Ben's
> current inventory and wardrobe will be retained but no longer tracked —
> changes in the chat will not be reflected when you turn it back on. Are
> you sure you want to do this?

- Desktop: `showWarmDialog<bool>` (`lib/ui/widgets/warm_dialog.dart:40`),
  `destructive: true`. A raw `showDialog` in a new file trips
  `raw_dialogs_ratchet_test` (CLAUDE.md:92,133). `Switch.onChanged`
  **awaits** the dialog and calls the setter only on `true`; the
  state-bound Switch needs no rollback on "No".
- Web: follow the PWA's existing destructive-action confirm (check chat
  delete in `web_ui/src/pages/`); if there is no reusable component, add a
  minimal themed confirm in the toggle path. The off-click is intercepted;
  the checkbox never flips until the POST returns (dismiss = no POST).

## Design

### 1. Switch storage

**1:1 — chat scalar.** `lib/services/chat/doors/controls/controls_door.dart`
(422 lines, cap 500 — watch it):

- `bool _pocketsChatSwitch` next to `_realismChatSwitch` (:65), surfaced
  like `chatPockets`/`setChatPockets`.
- `Future<void> setPocketsEnabled(bool enabled)`: set scalar; on enable with
  an empty record, seed from the card once; **never mutate the record when
  disabling** (comment in `setRealismEnabled`'s "Do NOT zero out" style,
  `:236-241`); then `deps.notify(); await deps.saveChat();` ("paint first"
  order from `setNeedsSimEnabled:294-297`).
- Live gate `bool get pocketsActive` — **one definition** (a
  `needs_gate_ratchet`-style pin): Porch Life global
  (`realismSettings.pocketsEnabled`) AND `_pocketsChatSwitch`. Porch Life
  vetoes live; the stored switch is the chat's own choice.

**Groups — per-member switch in the session blob.** `GroupMemberRealism`
already carries each member's pockets **record** in the per-member bag of
`group_realism_state` (`group_member_realism.dart:108-112`, deleted with the
chat by construction). Add the **switch** beside it:

- New key `static const pocketsSwitch = 'pockets_switch'` (:108-112 group),
  deliberately kept out of `GroupRealismKeys.runtime` like `pockets` itself
  (:119-149, :286-288), with a typed `bool?` accessor following the
  `nsfwCooldownEnabled` bool precedent (:244-246). Absent = not yet seeded.
- Setters mirror `setMemberAfterglowEnabled` plumbing:
  `ChatService.setMemberPocketsSwitch(mid, on)` (via `controls_door.dart` /
  `realism_api`), seeds-on-enable rule included, then `saveChat()`.
- No schema migration for groups — the bag already rides the session row
  and the group fork (`group_fork.dart:60,119-120`).

**Persistence (1:1).** Migration **v64** (`schemaVersion` 63 → 64,
`lib/database/database.dart:285`): byte-verbatim `if (from < 64)` block in
`lib/database/database.migrations.late.dart` adding
`pockets_enabled INTEGER` to `sessions`; column declared beside `pockets`
in `lib/database/database.tables.core.dart:207-218`. Save/load scalars in
`session_saver.dart:201-217` / `session_scalars.dart` **beside the
`realism_enabled`/`needs_sim_enabled` restore**, keeping "restore record
regardless of switch". fpchat head: `pockets_enabled` in
`captureHead`/`applyHead` (`session_seed.dart:228-290`).

### 2. Recompose the choke point

`PocketsLedger.pocketsEnabledFor(charId)`
(`lib/services/chat/pockets_ledger.dart:114-135`) is already the single
runtime gate. Recompose its body — card-flag reads **stop being runtime
law**:

```
pocketsEnabledFor(charId) =
    Porch Life global                          // live veto, unchanged
    && ( group chat ? memberBag(charId).pocketsSwitch   // per member
                     : _pocketsChatSwitch )             // 1:1
```

(`charId` stays for call-site stability; group lookup rides `_groupCharacters`
:120-125 to the member's mid, then the bag.) Every existing gate then keeps
working unchanged and automatically silences the model calls:

| Call site | What it gates |
|---|---|
| `pockets_pass.dart:74` | standalone `report_inventory` eval fire (`pockets_eval.dart:284-295`) |
| `reply_facts.dart:70-72` (`askPockets`) | fused pockets slice of the reply-facts call — per member, since the pass runs per scored reply per speaker |
| `pockets_ledger.dart:84` (`pocketsFor`) → `injection_wiring.dart:166-186` | per-turn `buildInventoryInjection` + `buildItemIntroInjection` (`inventory_injection.dart:98-165`) — a mixed group injects only the tracked members' lines |
| `pockets_ledger.dart:159,189` (`pocketsWriteAllowed`, add/remove) | hand edits from sidebar/PWA (`:181-307`) |
| `chat_tools_snapshot.dart:200-217` | web pockets panel payload (null ⇒ panel vanishes) — per member on the member feed |
| `character_state_group.dart:160,343` | desktop leaf visibility |
| `group_member_card_look.dart:263-266` | group member pockets row |

Additionally gate `greeting_picker.dart:238-255` re-seed on the live switch
— switching greetings while a track is off must not rewrite the retained
record.

### 3. Sidebar UI (desktop)

- **1:1:** `Switch` in the `pockets` leaf header
  (`character_state_group.dart` case `:333-369`), `NeedsLine` style
  (`needs_line.dart:60-71`): `value: chat.pocketsChatSwitch`, greyed when
  Porch Life vetoes or `chat.isGenerating`; extend the
  `porch_life_needs_gate.dart` note pattern for a pockets veto note. Render
  case and visible-portion id (`:158-161`) gate on the **live gate**, not
  the stored switch (Error Book 2026-10-08). Reorder wrapper rule:
  `ValueKey` on the direct child / `WheelPump`, never inside (Error Book
  2026-11-04: `2026-11-04-reorder-item-key-must-be-direct-child`).
- **Groups:** the switch sits on each member's pockets row —
  `group_member_card_look.dart:259-293` — the switch+panel pattern already
  exists in `wardrobe_chip_section.dart:180-211`. Off ⇒ the row shows only
  the switch + an "inventory retained, not tracked" muted note (the member's
  chips hidden, absent like the 1:1 leaf — never greyed inventory). Same
  rule for the group member leaf rendering in the Character State
  accordion (`sidebar_member_card.dart`, #706). Confirmation popup per
  §"Confirmation copy", member name interpolated.
- `character_state_group.dart` is 415 of a 500 cap; if it tips, extract the
  header+switch into `pockets_gate.dart` (new file: zero raw dialogs, zero
  raw colours).
- Theme: every colour via `AppColors.*Of(context)`, light + dark.

### 4. Defaults → new-chat seeding

**1:1 new chat** — `lib/services/chat/doors/entry/chat_entry.dart`, beside
the realism/needs seed (`:283-343`):
`_pocketsChatSwitch = ext.pocketsEnabled` (missing → **true**, today's
default). Porch Life keeps vetoing live through `pocketsActive` without
touching the stored choice (the `seedNeedsSim` ruling,
`needs_pass.dart:92-100`). Starting inventory seeds regardless and lands
hidden when the switch seeds off.

**Group new chat** — two-level AND, at
`lib/services/chat/doors/entry/group_entry.dart` (pockets seeding at
`:350`, beside realism/needs promotion `:270-312`):

```
memberSwitch(mid) := groupDefault(group definition) && memberCardDefault(ext.pocketsEnabled)
```

- `groupDefault` is a new field on the group definition blob
  `defaultMemberRealismState` (`lib/models/group_chat.dart:69`, persisted
  the way `_persistGroupTimeDay()` persists time —
  `group_realism_controller.dart:165-192`); **missing → true**.
- `memberCardDefault` rides each member's `group_members` ext copy
  (codec `pockets_enabled`, missing → true); the wizard already copies the
  source card's ext untouched (`group_member_extensions.dart:37`).
- Each seeded switch is written into the member's session bag (§1), so the
  mid-chat toggles own the value from chat start onward — the defaults
  never re-read at runtime.
- Sibling sites kept in sync: `new_chat.dart:160`, group wizard
  (`group_realism_step.dart`, `group_chat_committer.dart:106-183` carries
  defaults through), existing-chats retrofit offer
  (`existing_chats_offer.dart:142-145,197`) treats pockets like needs.

**Legacy derivation (D1, resolved).** A 1:1 session row whose
`pockets_enabled` is `NULL`, or a group member bag missing
`pockets_switch`, means the chat predates the feature: on open, derive
**once** from the member's/card's `pocketsEnabled` flag and write it, behind
the guard style that keeps card defaults from overwriting restored chats
(Error Book lesson at `chat_entry.dart:367-374`). Derived once, then the
stored switch is law — explicit OFF from the dialog survives reopen.

### 5. Settings surfaces

**Character editor + creator (default demotion, copy).** Switch UI stays,
meaning changes. `lib/ui/widgets/wardrobe_chip_section.dart:171-213` (key
`character-pockets-enabled`): subtitle gains "Sets the starting choice for
new chats with {name}; each chat can change its own." Same in
`realism_form_section.dart:126-131` / `identity_chip_lists.dart:198-199`
and the creator twin (`creator_realism_step.dart:93-95`). Storage
untouched (`front_porch_extensions_codec.dart:102,201`).

**Group settings — new-chats surfaces (both levels currently lack
pockets).**

- Group level: "Pockets & Wardrobe for new chats with this group" switch
  beside the Realism/Afterglow new-chat cards — desktop
  `master_toggle_cards.dart` family + wizard `group_realism_step.dart:209`
  (same "how new chats start it" framing), web
  `groupSetting/GroupNewChatsSection.tsx` (Realism at `:128-143`, Needs,
  Afterglow already live there). Writes the group definition blob field.
- Member level: per-member pockets default row on
  `realism_needs_tab/member_realism_card.dart`, cloning the Afterglow
  member switch precedent (`:53-70`
  `Switch(value: ext?.afterglowEnabled ?? true, … updateMemberAfterglow)`);
  twin `updateMemberPockets` → write the member ext via
  `GroupMemberExtPersister`/`persistGroupMemberExtensions`
  (`member_ext_persist.dart:12-30`, `controls_door.dart:367`). Worked
  example UI: group ON; Ben's row OFF; new chats start Mara+Shawn on, Ben
  off.

### 6. Web twin (same change, not a follow-up)

- Toggle route: `case 'pockets':` in `_toggle`
  (`chat_tools_routes.dart:112-166`), groups pass `extra: {memberId}` (the
  `toggle()` helper already sends extra, `ChatTools.tsx:102-103`) →
  `ChatToolsSwitches.setPocketsEnabled` / `setMemberPocketsSwitch`
  delegating to the same `ChatService` methods the sidebar calls
  (`chat_tools_switches.dart:35-46`).
- Snapshots: `pocketsSwitch` (stored) + `pocketsAllowed` (Porch Life) in
  `chat_tools_snapshot.dart:80-90`; per-member switches on the member
  realism feed (`chat_realism_read.dart:119-126` twin, live-gate rule from
  the needs precedent `:143-207`).
- `ChatTools.tsx` realism section (`:155-192` pattern): checkbox bound to
  the stored switch, greyed + note on `pocketsAllowed === false`, off-click
  confirm from §"Confirmation copy"; member-card checkboxes in the group
  member views. `ChatToolsShared.tsx` types additive with the "older host
  sends only X" fallback comment.
- `ChatToolsRealism.tsx` panel keeps vanishing on `!t.pockets` (already
  gate-driven via the snapshot).
- Group settings section + member rows per §5 web half.

## Out of scope

- No catch-up/retroactive extraction on re-enable (explicitly promised in
  the dialog).
- No split of Wardrobe into its own store or its own toggle — one switch
  covers pockets+wardrobe, matching the editor's "Pockets & Wardrobe"
  label.
- Chargen model calls (`gen_porch_life.dart`, `gen_greeting_writer.dart:83-105`)
  are card-creation paths, not chat-time; unchanged.
- Porch Life's global switch and `pocketTransfersEnabled` stay as-is.

## Tests

New guards must fail on the old code; no stubbed network; no scripted-model
answers (`CLAUDE.md`):

- `test/services/chat/pockets_chat_toggle_test.dart` — real
  `ChatService` + fake transport: 1:1 toggle off ⇒ a reply that adds an
  item produces **zero** pockets tool calls (standalone **and** fused), no
  injection fragment, record byte-identical before/after; toggle back on ⇒
  tracking resumes from the retained record, no re-seed over non-empty,
  hand-adds accepted again.
- Group per-member: group default ON + Ben card default OFF ⇒ new group
  chat seeds Mara/Shawn on, Ben off; Ben's mid-chat reply adds nothing and
  fires no pockets call while Mara's does; **flipping Mara off mid-chat**
  (setter-level dialog-free) silences her track only — everyone else
  unchanged; Mara's re-enable resumes from her retained record.
- Seeding/derivation: card default false → new 1:1 chat off with record
  seeded and hidden; missing default → on; legacy row (NULL column /
  missing bag key) derives once from the card flag and writes; explicit off
  survives reopen (red on the `currentSessionId` guard bug shape).
- fpchat round-trip + group fork carry the switch (column + bag key).
- Widget: toggle off opens the warm dialog with both buttons, 1:1 copy and
  group copy with the member's name; **No** leaves switch on, gate
  unchanged, no state write; **Yes** flips off, leaf/row absent (never
  greyed); switches bind the stored value, panels render on the live gate;
  Porch Life veto greys + notes.
- Golden updates for the Character State sidebar leaves + group member
  card (light + dark).
- `test/hygiene/`: run the shard; if a gate ratchet is added, pin the
  one-definition rule like `needs_gate_ratchet_test.dart:94`.
- Web: `ChatTools.pocketsToggle.test.tsx` (confirm before off, no POST on
  dismiss, checkbox bound to snapshot value, member toggle sends memberId)
  + `ChatToolsRealism` panel/member-row vanish on gate off.

## Hand-check

- [ ] Desktop 1:1: toggle off → dialog copy verbatim; No keeps everything;
      Yes keeps old chips, panel gone, next reply generates with no
      inventory line and no receipt chip; toggle on mid-conversation → old
      inventory back, new item in the next reply shows.
- [ ] Group (Mara/Ben/Shawn): group default ON, Ben default OFF in group
      settings → new chat has Mara+Shawn tracking, Ben quiet with his
      starting wardrobe hidden-but-retained; flip **Mara off mid-chat** →
      popup names Mara, Yes silences only her; Ben flip ON → his card
      wardrobe seeds once, then his replies start tracking.
- [ ] Close and reopen each chat while off: still off, inventories intact
      (1:1 column + group bag both survive reopen).
- [ ] Character editor default off → brand-new 1:1 chat opens off, card
      wardrobe hidden-but-seeded; existing chats unaffected.
- [ ] Porch Life global off vetoes live without burning stored/member
      choices (global back on → every choice exactly as left).
- [ ] Web: same flows incl. confirms and member toggles; desktop and web
      agree when both open.
- [ ] fpchat export/import and group fork preserve switches.

## Decisions (resolved 2026-11-04)

- **D1 — legacy chats:** derive the switch **once from the card flag** on
  first open after upgrade, then the stored switch is law. ✔
- **D2 — groups:** per-member switches, toggleable at will mid-chat from
  each member's sidebar card with the same warning popup; starting state =
  group new-chat default AND per-member card default (group ON + Ben OFF ⇒
  Mara and Shawn on, Ben off at chat start). ✔
- **D3 — confirmation copy:** cleaned-up wording approved; group variant
  interpolates the member's name. ✔
