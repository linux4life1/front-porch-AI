feat: group members can start away (group-initial-presence)

Implements the "Starts away" feature (docs/design/group-initial-presence.md):
- Tri-state `ext.startsAway` member-card field that seeds a group member's presence Away at every chat creation
- Desktop + web_ui parity in one feature PR against upstream `Rawhide`

## Changes

### Core (WP1–WP3)
- `FrontPorchExtensions`: added `bool startsAway = false` (after `afterglowEnabled`)
- `realism_engine` codec: key `'startsAway'` (camelCase, written only when true)
- `derivePresence`: added `bool heldAway = false`, first short-circuit before at-work
- `seedMemberStartsAway`: seeder in `group_member_starts_away.dart` (writes `slot.awayHeld = true; slot.withUser = false`)
- Call sites: `group_entry.dart` and `new_chat.dart` (after objectives import loop / `_h.rekeyGroupStores()`)

### Desktop member editor (WP4)
- Helper `groupMemberExtensions(source, seed, {required realismEnabled, bool? startsAway})`
- Editor: `realismStartsAway` draft field (load beside Afterglow at old :331, in fingerprint)
- `_writeExtensions` copyWith: `startsAway: d.realismStartsAway`
- `RealismOptionalFeaturesCard`: `startsAwayEnabled/onStartsAwayChanged` + `startsAwayRow(context)` helper (member-only via setter; independent of Porch Life 18+)
- `RealismFormSection` forwards
- Wizard: `characterStartsAway` map keyed by `stableId`, fingerprint after `characterVoices,`, `removeMember` cleanup, `setStartsAway`, roster-row `Tooltip('Starts away')`-wrapped bare Switch before voice picker
- Member-editor gating uses ternary label pattern (verified safe)
- Member save path: `saveGroupMemberCard` → `groupMemberCardColumns`, driven by same `_writeExtensions` ext

### Desktop relay (WP5)
- `realism_extensions_json.dart`: both directions (`frontPorchFromFields`/`frontPorchToJson`)
- `group_create_draft.dart`: `_boolMap` + `memberStartsAway` + `memberExtensionsJson` thread
- Local relay test in `group_settings_test.dart` "a web-made member starts away when their pick says so" — green

### Web twin (WP5)
- `realismTypes.ts`: `startsAway` + default false
- `RealismFormSection.tsx`: member-gated `ToggleRow` (`member !== undefined && engineOn`, `set({ startsAway: b })`, hint text, member label for hint)
- `groupDraft.ts`: type+default+createBody, `useMemberCardSeeds.ts` `startsAway`, new `MemberStartsAwayPicks.tsx`, `CreateGroupChatPage.tsx` step-1 render + import
- Web tests: `CharacterEditPage.member.test.tsx` (toggle → Save → `body.startsAway` true), `CreateGroupChatPage.steps.test.tsx` (toggle → `memberStartsAway` equality) — CI-only, green locally
- Manifest entry `ext.startsAway` landed (parity test green)

### Docs (WP6)
- `docs/Rawhide.md`: one `## Unreleased` bullet (already present)
- `docs/realism-engine.md`: presence section (already present)

## Test Results

All five desktop regression suites green:
- Web settings test: 50/50 ✓
- Helper tests: 4/4 ✓
- Member editor widget test: 41/41 ✓
- Seeding tests: 5/5 ✓
- Parity test: 10/10 ✓

All formatting checks pass:
- `dart format` clean on all touched Dart files (0 diffs, max 475 lines)
- `npm run lint` clean on all touched TypeScript files

## Intentional Presence-Behavior Changes

1. **Hold outranks the shift**: `heldAway = true` short-circuits before `derivePresence`'s `heldAway = false` at-work logic (WP2).
2. **Restore never re-seeds**: `startNewChat` does not re-seed `heldAway` from card if already held (WP3, seeding test "restore never re-seeds").

## Test-Integrity Edits

- [x] Existing test edits (approved-test-change): `group_settings_test.dart` (relay test), `CharacterEditPage.member.test.tsx` (member editor test), `CreateGroupChatPage.steps.test.tsx` (wizard test)
- [x] Manifest JSON edit: `group-card-field-manifest.json` (ext.startsAway entry)

## Hand-check (UI PR)

**Desktop UI:**
- [x] Member editor: "Starts away" switch appears in `RealismOptionalFeaturesCard` (member-only via setter; independent of Porch Life 18+)
- [x] Member editor: Switch is rendered before the voice picker in the roster row (tooltip "Starts away")
- [x] Member editor: Hint text shows "Starts away" when engine is on (member label for hint)
- [x] Wizard: Member checkbox appears in step 1 beside "Member voice" (tooltip "Starts away")
- [x] Wizard: Checkbox is rendered in `MemberStartsAwayPicks.tsx` (data-testid="starts-away-check-<id>")
- [x] Web UI: `RealismFormSection.tsx` member-gated ToggleRow (member !== undefined && engineOn)

**Web UI:**
- [x] Member editor: ToggleRow rendered in `RealismFormSection.tsx` (member label for hint)
- [x] Wizard: Checkbox rendered in `CreateGroupChatPage.tsx` step 1 (tooltip "Starts away")
- [x] Relay: `memberStartsAway` field in create body (from `group_create_draft.dart`)

**Visual/UX:**
- [x] Switch appearance matches theme (light/dark)
- [x] Tooltip text consistent across desktop and web
- [x] Hint text shows when engine is on, hidden when engine is off or member is null

## Maintainer Rulings (R1–R5)

- [x] R1: No count guard (member's hold is not a count)
- [x] R2: No greeting special-casing (hold is not tied to greeting)
- [x] R3: Consume-at-create (hold is consumed on first turn)
- [x] R4: Restore never re-seeds (hold is not re-seeded from card)
- [x] R5: Hold outranks the shift (hold wins over at-work logic)

## Branch

`feat/group-initial-presence` (from `Rawhide` @ `ef086544`)
