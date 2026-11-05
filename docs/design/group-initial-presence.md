# Starts away — seeding a group member's initial presence

A role-playing user wants to designate one or more (but **not all**) group
members as not initially present, using the existing **Away** status. The
setting lives in the Group editor.

This document plans that. Presence itself is already both derived and
runtime-editable; what is new is a *starting seed the user can put on a
member*. Anchors below are from the Rawhide tree at `c96e3059`
(2026-11-04). The ratchets and tests, not this file, are the law.

## How presence works today

- Presence is an enum, not a column:
  `PresenceWhere { withYou, away, atWork }`
  (`lib/ui/chat_components/sidebar/character_state/presence_word.dart`).
- One derivation, deliberately singular:
  `derivePresence()` in `lib/services/chat/presence_derive.dart` — order is
  **At work** (occupation + stretch of hours + workDays against the live
  story clock) → **Away** (`!inScene`) → **With you**. Its own header
  comment: "With you / Away is last. Never a yes/no switch."
  `workFieldsForMember` exists precisely so "the member card's at-work
  word, the turn skip, the web cast and the prompt" cannot disagree.
- **Manual away already exists at runtime.**
  `AwayPulseRunner.setGroupMemberAway(memberId, away:)`
  (`lib/services/chat/doors/cast/away_pulse_runner.dart:173-184`) writes the
  member's state slot: `awayHeld = away; withUser = !away`, through the
  per-member realism state keys in
  `lib/services/chat/group_member_realism.dart` (`GroupRealismKeys.awayHeld`,
  `:72`, getter/setter `:224-229`). Two pinned semantics matter:
  once held, only the user's **Back** clears it (`:214-216` — nothing else
  may un-away a held member), and the away pulse respects the hold
  (`isHeld`, `:100`) instead of re-deciding it. `releaseHeldAway`
  (`:195-197`) is the explicit release. The sidebar's `presence-toggle` and
  the web cast's `onSetAway` (`web_ui/src/components/CastBar.tsx:85-92`)
  both drive it.
- At **chat start**, presence is inferred: every member seeds as in-scene
  ("presence-inference" notes at
  `lib/services/chat/doors/entry/group_entry.dart:282`,
  `doors/session/new_chat.dart:263`,
  `doors/session/session_seed.dart:193`). With nobody away unless a shift is
  live or a judge said they left, nobody has *chosen* absences today.
- Today's wrinkle the feature also fixes (see R2): the glance, skip and
  prompt read `derivePresence` without the hold, so a member held away while
  **on shift** reads "At work" everywhere — which happens to break the
  mental model exactly where a user-specified seed would be most visible.

One chat-creation choke point already does per-member, once-per-fresh-chat
seeding: the starting-quest/objectives loop at
`doors/entry/group_entry.dart:370` ("Each member's authored starting quest,
imported once per fresh chat"). The seed joins that pattern, not a new
lifecycle.

## Decisions (maintainer rulings, 2026-11-04)

| # | Question | Ruling |
|---|----------|--------|
| D1 | When is the seed applied? | **Every fresh chat — the never-opened group's first open *and* every explicit new chat — never mid-chat.** |
| D2 | Initial-away vs. an active shift | **Held away wins.** Away — not At work — is what a seeded, held member is, everywhere presence is read. |
| D3 | Restore vs. re-seed | **Live state persists; the seed applies only at chat creation.** Re-opening a session never re-seeds. |
| D4 | The "not all" constraint | **Retracted; no count rule anywhere.** The app already tolerates a cast that is all Away/At work (banner turns, no special handling); the seed adds none. |
| D5 | Greeting attribution when the first member starts Away | **No special handling, for consistency**: it already happens when the first member is At work today. |
| D6 | Does the seed follow the member? | **Only the chat-creation seed matters.** Members added mid-chat start present; the setting applies from the next chat onward. |

## The rules the implementation must satisfy

- **R1 (D1 + D3 — when).** The seed applies exactly when a group chat
  session is created: the never-opened group's first open, and every
  explicit new chat. It is never re-applied on session restore: the restored
  per-member state — held flags included — always wins, so a member the user
  pulled Back stays Back across reloads. Flipping the editor's switch while a
  chat is open never teleports anyone mid-conversation; it takes effect at
  that group's next chat creation.
- **R2 (D2 — what wins).** A held member is **Away**. The hold outranks the
  shift at every read: the glance word, the turn skip and its banner, and
  the prompt-line chooser must all answer from one verdict (the same
  "one read" discipline `derivePresence` already imposes). Mechanism: the
  derivation gains the hold as an input —
  `derivePresence(..., heldAway)` defaults false and short-circuits to
  `PresenceWhere.away` **before** the at-work branch — and the single
  member-presence accessor (`cast_api.groupMemberPresence`,
  `doors/cast/cast_api.dart:145-146`, fed by
  `away_pulse_runner.groupMemberPresence:151-156`) passes the slot's
  `awayHeld` so callers cannot disagree. 1:1 characters have no hold and
  change nothing: their glance, always-in and turn handling stay as today.
  The away pulse already respects `isHeld` and needs no change.
- **R3 (D4 — no guard).** No validation that at least one member stays
  present, neither in the wizard nor the editors nor the web. An all-away
  chat behaves exactly as an all-away chat behaves today: every turn
  resolves to the Away banner (`groupTurnSkips` →
  `presenceSkipBanner`, `doors/turn/group_speakers.dart:155`), the clock
  still runs, nothing special-cased.
- **R4 (D5 — greeting).** The opening message resolves exactly as today:
  a custom group first message belongs to the group as narrator; the
  fallback speaks the **first roster member's** greeting even when that
  member starts Away — identical to how an At-work first member is treated
  today. No pick-a-present-member logic.
- **R5 (D6 — consume at create).** The seed is read at chat creation and
  consumed there. Mid-chat member add, member move or editor edits do not
  re-run it; they shape the *next* created chat.

## Data model

A new member-card extensions field:

- Field: `startsAway` — `bool`, tri-state like `workDays` (the codec's own
  pattern, `lib/models/character/front_porch_extensions_codec.dart:47-56`):
  **key missing or null → present** (the default; old members never encoded
  it); **written `true` → starts away**. Written false is simply omitted —
  the codec already omits nothing-fields, mirroring how `awayHeld` deletes
  its key when cleared.
- Home: `lib/models/character/front_porch_extensions.dart` (the class whose
  fields the member row carries as one `ext` JSON blob — "the row stores
  the whole extensions, every field the codec writes",
  `group-card-field-manifest.json` spine).
- No migration, no codegen ceiling: the column is the existing extensions
  blob. `group-card-field-manifest.json` gains the field with editor
  pointers (both editors below) and a creation-time reader pointer (the
  seeder), per `test/hygiene/group_card_field_parity_test.dart`. Because the
  field *is* group-editable by design, it must **not** join
  `memberHidden` (the list of switches the member editor must hide) — that
  map is exactly for switch fields a member must not see as options.
  Editing the manifest is a test-integrity edit: it needs the maintainer's
  `approved-test-change` label on the PR.

## Where the seed applies

One seeder, two call sites, one writer:

- The seeder takes the member roster and, for each member with
  `startsAway`, writes the state slot exactly the way the runtime toggle
  does (`awayHeld = true; withUser = false`) — the same slot accessor, so
  the manual toggle, the away pulse and the seed cannot disagree about who
  is held.
- Call sites, both inside creation:
  1. **First open of a never-opened group** — the fresh-chat branch of
     `doors/entry/group_entry.dart` (the greeting-creation branch; the
     objectives seed at `:370` is the shape to sit beside).
  2. **Every explicit new chat** — the group branch of
     `startNewChat` (`doors/session/new_chat.dart`, beside the
     presence-inference note at `:263`).
- Session restore (`_loadLastSession` → the group restore keyed by message
  speaker, `doors/realism/realism_restores.dart`) is **not** a call site.

## Editor surface (desktop)

The control is a plain switch labelled **Starts away** on each member — a
setting, not a status lamp; the lamp stays derived as today.

1. **Creation wizard — cast step**
   (`lib/ui/pages/create_group_chat_page/group_cast_steps.dart`, the
   reorderable cast list; the committer
   `group_chat_committer.dart` persists member rows already, and the
   switch rides the draft).
2. **Member editor** — the per-member switch panel a member edit already
   surfaces (`edit_group_details_tab.dart` opens Edit Character on a
   member per the manifest spine; the member's group switches render in
   `edit_character_page/edit_character_realism_section.dart` per the
   manifest's `memberHidden` map being the *hide* list for that panel).
   New switch joins that panel, clearly distinct from the live presence
   word. One helper line: applies when this group's chats are created; the
   Back control clears it for the current chat.

Both editors write through the existing member-card save paths
(`saveGroupMemberCard` / codec), so no new write machinery.

## Web twin

Same field, same three surfaces (parity is mandatory in the same change):

- Creation: `web_ui/src/pages/CreateGroupChatPage.tsx` cast step — a
  "starts away" switch per member, to match the wizard.
- Member edit: `CharacterEditPage.tsx` in member mode (its
  `member.test.tsx` is the existing guard) — the switch next to the same
  per-member group switches desktop shows
  (`web_ui/src/components/realism/memberGroup.tsx` area; the work-hours
  codec twins already prove the pattern in
  `web_ui/src/components/realism/workHours.ts`).
- Runtime: `CastBar.tsx` already shows presence words and Away/Back — no
  change, only the seed's verdict flowing out of the shared read.

## Statement of work

One feature PR; packages as review units.

- **WP1 — codec + manifest.** `startsAway` on the extensions class and
  codec (survives save/restore round-trip); manifest entries with both
  editor pointers and the creation reader pointer. Not joining
  `memberHidden`. `approved-test-change` label needed for the manifest file.
- **WP2 — held precedence.** `derivePresence` gains the default-false
  `heldAway` short-circuit before the at-work branch; the member-presence
  accessor passes `awayHeld`. All reads switch to it. 1:1 untouched.
- **WP3 — seeder.** The per-member seed function and its two creation call
  sites; creation-only guard proven by the restore test.
- **WP4 — desktop editors.** Wizard cast step + member editor switch; no
  count validation (R3).
- **WP5 — web.** Cast step + member editor switch on
  `CreateGroupChatPage.tsx` / `CharacterEditPage.tsx`; `npm test` guards;
  parity manifest rows if the per-member switch manifest requires them.
- **WP6 — tests + docs.** See the table; plus one `## Unreleased` bullet in
  `docs/Rawhide.md` and the presence section of `docs/realism-engine.md`
  updated with the held-precedence rule.

## Tests (each must be red before its fix lands)

All in the guards' existing homes; the presence test files
(`test/services/chat/presence_derive_test.dart`,
`test/services/chat/away_return_integration_test.dart` family,
`test/ui/pages/create_group_chat_page/` wizard tests,
`test/ui/settings/…` member-editor tests as applicable) — new `test(`
blocks, no helper edits.

1. **Seed at first open** — a member row with `startsAway` opens fresh:
   glance says Away, first turn is the away banner, card dimmed.
2. **Seed at new chat** — same on an explicit `startNewChat` of an existing
   group.
3. **No re-seed on restore (R1)** — seeded away, user presses Back
   mid-chat, app or page reload restores the session: the member is still
   present. Red if the seeder runs on restore.
4. **Hold outranks the shift (R2)** — `startsAway` member whose shift is
   live at creation reads *Away* (word, banner variant, no at-work prompt
   line). Red against today's at-work-before-away order.
5. **Manual parity** — pressing Back clears the hold for the session
   (`releaseHeldAway` semantics), then a *new chat* re-seeds it. Red if
   either half is missing.
6. **No count guard (R3)** — every member switchable to away; the chat
   proceeds with banner-only turns as today.
7. **Greeting attribution (R4)** — first roster member with `startsAway`
   still owns the fallback greeting. Existing contract, extra case.
8. **Codec round-trip** — `startsAway` written true survives
   `saveGroupMemberCard` and the web member save; absent/false decode to
   present.
9. **Web** — the wizard and member-editor switches write the field; a
   component test per surface plus the parity manifest row.
10. **Derived-1:1 invariance** — a 1:1 character with the same fields
    derives exactly as today (held default false; glance may never regress
    the 1:1 With you / Away judge).

## Non-goals

- No "starts at work", no per-weekday schedules.
- No validation that someone stays present; no all-away handling.
- No greeting pick-a-present-member logic (R4).
- No change to the away pulse, idle autonomy, the turn wheel or the 1:1
  guest flow beyond the held-aware read.
- No new web group-settings surface beyond existing member-edit paths.

## Poke script (maintainer, ~60 s)

1. Edit a group → two members → flip **Starts away** on both → save.
2. Open the chat: both cards show the dimmed **Away** word; sending a
   message gives their turns as away banners, not replies.
3. Press **Back** on one: word returns; if on shift it may show
   **At work**; they can speak now.
4. Close, reopen the chat: that member is *still* Back (rule R1).
5. Start a new chat in the same group: both are Away again (rule R1, the
   creation seed).
6. Web: same flow on the phone — same field, judge from the cast bar.

## Residual risks worth a reviewer's eye

- R2 deliberately changes today's display for *manually-away-on-shift*
  members (At work → Away). That is the point of the ruling, but every
  presence-word snapshot in tests and goldens that involved a held member
  on a live shift must be re-examined, not auto-updated.
- The seeder must run after member-state hydration and before the first
  pulse tick; a race would show a one-glance "With you". Test 1 and test 2
  pin the verdicts, and the away pulse's `isHeld` keeps holds stable once
  written.
- Web settings parity manifests: the field rides member-edit payloads, but
  whichever per-member switch manifest the maintainer's tests read must be
  updated in the same change — a drifted manifest is a CI failure, which is
  the safety net, not the goal.
