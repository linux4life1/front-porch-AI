# PR 5b — Chaos Mode per character (sketch)

Acceptance (maintainer, 2026-11-12): "Tea, Joey and Yugi are in a group
chat. Joey has chaos mode on while Tea and Yugi have it off. It needs to
have the same toggle for groups as we do in 1:1 chats and it needs to work
the same way."

## 1. Group chat sidebar — focused-member model (maintainer, 2026-11-12)

The cast bar at the top selects the focused member — that selection
drives which member's chaos state the Story Tools Chaos card shows. This
is the model the sidebar already uses: the member card below the cast
bar shows the focused member, "Objectives · Sophia" is the focused
member's, and the web Realism/Needs/Afterglow switches already follow the
focused member and post with their `memberId`. Chaos joins that set; the
group-wide locked row (the padlock in the maintainer's screenshot)
retires with this PR.

```
┌ (●)Joey  (Tea)  (Yugi) ── cast bar ────────┐   ← 🎲 badge on faces
└────────────────────────────────────────────┘     whose chaos is ON
┌ Story Tools ────────────────────────────────┐
│ ▾ Chaos (Chance Time)            Joey       │   ← focused member's
│   Chaos Mode                   [ ● ON ]     │     name in the header,
│   Pressure ▓▓▓▓▓▓▓░░░░  64%                 │     like "Objectives
│   [ 🎲 Spin now ]   18+ events [ ● ]        │     · Sophia"
│   ~ an event lands about every 2 replies    │
│                                             │
│   (select Tea or Yugi → the card shows      │
│    theirs: switch off, gauge and Spin        │
│    hidden, exactly like a 1:1 with chaos     │
│    off)                                     │
└─────────────────────────────────────────────┘
```

- Acceptance flow (maintainer): select Joey → toggle Chaos on; select
  Tea, then Yugi → each shows the switch off. The card always reflects
  the selected member; toggling writes only that member's switch
  (`{name:'chaos', memberId, value}`).
- Dice badge on cast-bar faces whose chaos is on — same slot as the
  status dots, both surfaces — so on/off across the cast is visible
  without selecting each member.
- Spin spins the **focused member's** wheel; the reveal modal names them
  (matches how the spin already names the next speaker).
- A member who left the cast loses the badge; their pending event drops.

## 2. Chance Time scoping ("only reaches that member")

Today the chat holds one chaos state and the event is appended to whoever
speaks next. Per member means:

- A pending event belongs to a member. It injects **only on that member's
  turn**, and `{{char}}` resolves to them. `{{user}}`/`{{other}}` unchanged.
- An event that is pending for Joey is never consumed by Tea's turn; it
  waits (it does not expire early, does not ride another member).
- Auto-roll happens on a member's own turn only when their switch is on —
  the pressure tick for Joey must not tick Tea (Error Book
  `2026-10-06-needs-v2-clock-off-group-tick-everyone`: per-member state
  was ticking everyone; this is the same trap).
- 1:1 behaviour is bit-for-bit unchanged (shared wheel maths and vectors
  stay green).

## 3. Data model — no schema bump

- **New-chat default (the editor toggle):** the member's card already
  carries `frontPorchExtensions.chaosModeEnabled` on the member row. The
  member-mode editor toggle un-greys and edits that value (the greyed
  "set per group for now" lock retires with this PR).
- **Live per-chat state:** new keys in the `GroupMemberRealism` blob
  (`sessions.group_realism_state`, same JSON bag as the per-member
  Realism/Needs/Afterglow/Pockets switches): `chaosSwitch`,
  `chaosNsfw`, `chaosPressure`, `chaosPendingEvent`. Persisted with the
  chat; no v68, no new columns.
- **Seeding (one-time, `??=`, never rewritten)** in
  `member_switches.dart seedMissing()`, same shape as the existing rows:
  member already has a stored value → keep it; else seed from their card
  default; a card without one falls back to the **group's** switch seeded
  **once at migration of the feature** (Error Book
  `2026-10-09-new-group-default-applied-to-legacy-import` — existing
  groups seed every member from the group's current switch, one time;
  after that the member's switch is independent).
- `reseed()` (1:1 → group) and member-join paths seed the new keys the
  same way they already handle the others.

## 4. Service and pipeline

`ChaosModeService` stays one instance per chat but its state becomes
per-member maps keyed by member id in groups (1:1 keeps the scalar path
untouched). Pressure tick, cooldown, auto-roll, and
`pendingChaosInjection` all resolve against the member whose turn it is.

- `checkAndTickChaosPressure` in a group: tick only cast members whose
  `chaosSwitch` is on, at the point their turn completes.
- `chanceTimeSpeakerName` stays the fallback for 1:1; group spins carry
  the member id.
- Continue still must not consume one-shots (existing guard, now
  per-member).

## 5. API (web twin)

- `/api/chat/tools/toggle`: add `chaos` and `chaosNsfw` to the
  `memberToggles` map — `{name:'chaos', memberId:'m1', value:true}`.
- `/api/chat/chance-time/spin`: optional `memberId` (group); absent = 1:1.
- `/api/chat/tools` snapshot: in a group the `chaos` block keeps its 1:1
  shape but reports the **focused member** and carries their `memberId`
  (the snapshot already does this for realism/needs/afterglow); plus a
  cast digest `chaos.cast: [{memberId, name, enabled}]` so both surfaces
  can paint the cast-bar badges without selecting each member.
- WS `chance_time` edge carries the member id + name for the modal;
  toggles/spins for a non-focused member still refresh the digest.

## 6. Editors

- **Member editor (desktop + web):** Chaos Mode row editable again
  (un-grey), tooltip changes from "set per group for now" to "this
  member's default for new chats".
- **Group editor Cast rows:** each member row gets a compact "Chaos"
  tri-state (default = their card value) next to Strength — same row
  pattern as `web_ui/src/pages/GroupEditPage.tsx` Advanced Prompts.
- **New-group wizard:** the group-level chaos card stays as the cast-wide
  preset (sets every member's row at once); per-member rows then win.
- The group row keeps `chaos_mode_enabled`/`chaos_nsfw_enabled` columns —
  legacy seed source and cast-wide preset only; generation no longer
  reads them.

## 7. Guards that must change with the feature

- `test/hygiene/one_ui_parity_test.dart:1024-1058` (member editor greys
  chaos) and the `:383` group leaf list.
- `web_ui/src/pages/CharacterEditPage.member.test.tsx:105` (the tooltip).
- `test/baselines/chat_service_api.json` (new per-member methods).
- `chaos_wheel_test.dart:494-629` group speaker tests — extended with
  "an event for Joey waits for Joey" and "Tea's tick ignores Joey".
- Goldens: sidebar chaos (1:1 unchanged) + new group-sidebar chaos
  golden; `group_editor` goldens (member row un-greyed).

## 8. Deliverables (desktop + web in one change, One UI)

1. `GroupMemberRealism` chaos keys + seed/reseed + `member_switches`
   setters.
2. `ChaosModeService` per-member scoping + turn/pressure/injection
   scoping; 1:1 scalar path kept.
3. Desktop: `ChaosPanel` in group mode becomes the focused member's —
   name in the header (like "Objectives · Sophia"), switch/18+/gauge/Spin
   post with the member id; locked group-wide row retired; dice badge on
   cast-bar faces; reveal modal names the member.
4. Web: `ChatToolsChaos` follows the focused member the same way the
   Realism/Needs switches already do; cast-bar badge; wire as §5.
5. Member editor un-grey + new tooltips (both surfaces); group editor
   Cast row chaos control (both surfaces).
6. Tests above, vitest twins, goldens; hygiene suite before push.
