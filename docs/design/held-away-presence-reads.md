# Held away — every presence read must consult the hold

A member whose Away is **held** — the user's hand-set Away, or a card seeded
"starts away" (docs/design/group-initial-presence.md) — must read as held
everywhere presence is read. Today three surfaces derive that member's
presence without ever passing `heldAway`, so a held member mid-shift shows
"Away" on their cast chip, "At work" in the sidebar Time leaf, and gets an
at-work line in the prompt. This document planned closing that; the
follow-up PR implements it (the surface table and the rulings below record
the landed shape). Anchors are
from the Rawhide tree at `15ca4571` (2026-11-14). The ratchets and tests,
not this file, are the law.

## The rule the code already states

`GroupMemberReads.awayHeldForGroupCharacter`
(`lib/services/chat/doors/entry/group_member_reads.dart:71-78`):

> Only Back clears it, so every presence read of this member feeds it to
> [derivePresence] — the hold must not disagree with the card.

`derivePresence` itself already honours it when told
(`lib/services/chat/presence_derive.dart:127` — `if (heldAway) return
PresenceWhere.away;`, ordered ahead of the shift per R2/R5 of
group-initial-presence.md). The gap is the callers that never tell it.

## Surfaces, wired and not

| Surface | Read site | Feeds `heldAway`? |
| --- | --- | --- |
| Cast chip (Away/Back control) | `lib/ui/widgets/group_member_card.dart:233` | yes |
| Speaker skip (turn order) | `lib/services/chat/doors/turn/group_speakers.dart:91,166` | yes |
| Away pulse | `lib/services/chat/doors/cast/away_pulse_runner.dart:86,168` | yes |
| Sidebar Time leaf, member word | `lib/ui/chat_components/sidebar/character_state/character_state_leaves.dart` (`_memberWord`) | yes — via the shared read |
| Position injection (prompt) | `lib/services/chat/prompt_injection/behavioral_injection.dart` (`buildPositionInjection`) | yes — `getHeldAway` |
| Plan injection's at-work gate | `lib/services/chat/prompt_injection/plan_injection.dart` | yes — `getHeldAway` |

The 1:1 sidebar leaf (`character_state_leaves.dart:194`) has no hold to
read — holds are group-member state — and its "Away / Back lives on the
cast chip" comment predates holds; the group member word grew its own
`_memberWord` and inherited the 1:1 call shape without the hold.

On the web, member presence reaches the UI through the facade's cast data
(`CastBar.tsx`), which rides the wired path above; the web sidebar has no
member time-word surface of its own, so web needs no read of its own
(verified against `web_ui/src` — no independent `derivePresence` for
members).

## Rulings

- **H1 — a presence read is wrong if it can disagree with the hold.** No
  surface may derive a group member's presence without passing
  `heldAway`. A held member reads held everywhere or the reads lie to
  each other, which is exactly the disagreement `workFieldsForMember`
  was built to prevent for the at-work word.
- **H2 — a seeded hold and a hand-set hold read identically.**
  `heldAway` is one bit wherever it is read; which kind it is (chip
  label "Away" vs the pulse's own wording) is the chip's and the pulse's
  concern, not the readers'. A seeded hold with no turn run yet derives
  like any other hold.

## The shape that landed

One shared read, so no future call site can forget the hold:

- `RealismGraph.presenceWhereForMember(CharacterCard)` in
  `realism_api.dart` returns `derivePresence(...)` with `heldAway` from
  the member's group slot, the work fields the group store already
  resolves (library fallback included), and the stance/withUser/clock
  the readers used to assemble. It hangs off `chat.realism` on purpose:
  `ChatService`'s public surface is pinned by
  `test/baselines/chat_service_api.json`, and a new read needs no new
  name on the shell.
- Convert the three surfaces to it. `_memberWord` keeps its
  read-only-word rendering; `buildPositionInjection` then takes the
  1:1's away branch for a held member ("Away from {{user}}$here. Write
  from there.", `behavioral_injection.dart:104-107`) instead of the
  at-work line; the plan gate's `atWork` check stops suppressing the
  plan line of a member the chat is holding away (moot for speakers —
  held members are skipped — but the read stops lying).

## Rulings on the open questions

1. Prompt line for a **seeded** hold with no turn run: the same 1:1
   away line, "Away from {{user}}$here. Write from there." (H2 — a hold
   is a hold; which kind it is stays the chip's and the pulse's
   concern). Decided 2026-11-18, implemented.
2. Sidebar word: "Away" outright, no greyed at-work word beside it (H2
   — one bit, reads identical). Decided 2026-11-18, implemented.
3. Plan gate: the honest read is all this surface needs — the hold
   rides with the derive (H1), so a held member's plan line is not
   suppressed mid-shift. Decided 2026-11-18, implemented.

## Test plan (landed)

- **Sidebar leaf**: a member held (hand-set and seeded variants, H2)
  with an occupation window open reads "Away" in the Time leaf —
  `test/ui/chat_components/group_away_on_cast_chip_test.dart`.
- **Position injection**: held + mid-shift member → the away line, not
  `atWorkPromptLine` — `test/services/chat/group_work_prompt_injection_
  test.dart`, through the wired injection.
- **Plan injection**: held + mid-shift member → plan line present (the
  gate no longer suppresses it) — `test/services/chat/plan_injection_
  test.dart`.
- **Parity**: `one_ui_parity_test` continues to pin that web reads the
  same cast presence — no new web surface, so no new web test beyond
  the existing cast coverage.
