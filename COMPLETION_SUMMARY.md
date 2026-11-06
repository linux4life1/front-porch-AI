# Group Initial Presence — Completion Summary

## Feature: "Starts Away" (WP1–WP6)

### Overview
Tri-state `ext.startsAway` member-card field that seeds a group member's presence Away at every chat creation. Desktop + web_ui parity achieved in one feature PR against upstream `Rawhide`.

### Completed Work

#### WP1: FrontPorchExtensions field
- ✅ `bool startsAway = false` on `FrontPorchExtensions` (after `afterglowEnabled`)
- ✅ Codec key `'startsAway'` in `realism_engine`, camelCase, tri-state (written only when true)
- ✅ No DB migration required

#### WP2: derivePresence
- ✅ `bool heldAway = false` added to `derivePresence`
- ✅ First short-circuit before at-work
- ✅ Deliberately unchanged: `character_state_group.dart:384`, `chat_tools_scene.dart:126`, `behavioral_injection.dart:90`, `plan_injection.dart:47`

#### WP3: Creation seeder
- ✅ `seedMemberStartsAway(members, store, {required String Function(CharacterCard) idOf})` in `lib/services/chat/doors/entry/group_member_starts_away.dart`
- ✅ Write order: `slot.awayHeld = true; slot.withUser = false` (load-bearing, `withUser` setter refuses while held)
- ✅ Runs outside every realism gate via `memberForWrite`
- ✅ Call sites: `group_entry.dart` (fresh-chat branch, after objectives import loop) and `new_chat.dart` (group branch, after `await _h.rekeyGroupStores()`)

#### WP4: Desktop member editor
- ✅ Helper `groupMemberExtensions(source, seed, {required realismEnabled, bool? startsAway})`
- ✅ Editor: `realismStartsAway` draft field (load beside Afterglow at old :331, in fingerprint)
- ✅ `_writeExtensions` copyWith: `startsAway: d.realismStartsAway`
- ✅ `RealismOptionalFeaturesCard` gained `startsAwayEnabled/onStartsAwayChanged` + `startsAwayRow(context)` helper (member-only via setter; independent of Porch Life 18+)
- ✅ `RealismFormSection` forwards
- ✅ Wizard: `characterStartsAway` map keyed by `stableId`, fingerprint after `characterVoices,`, `removeMember` cleanup, `setStartsAway`, roster-row `Tooltip('Starts away')`-wrapped bare Switch before the voice picker
- ✅ Member-editor gating uses ternary label pattern (verified safe)
- ✅ Member save path: `saveGroupMemberCard` → `groupMemberCardColumns`, driven by same `_writeExtensions` ext

#### WP5: Relay + Web twin
- ✅ Desktop relay: `realism_extensions_json.dart` both directions
- ✅ `group_create_draft.dart` `_boolMap` + `memberStartsAway` + `memberExtensionsJson` thread
- ✅ Local relay test added in `group_settings_test.dart` "a web-made member starts away when their pick says so" — green
- ✅ Web types: `realismTypes.ts` (`startsAway` + default false)
- ✅ Web member editor: `RealismFormSection.tsx` member-gated `ToggleRow` (`member !== undefined && engineOn`, `set({ startsAway: b })`, hint text, member label for hint)
- ✅ Web wizard: `groupDraft.ts` type+default+createBody, `useMemberCardSeeds.ts` `startsAway`, new `MemberStartsAwayPicks.tsx`, `CreateGroupChatPage.tsx` step-1 render + import
- ✅ Web tests: `CharacterEditPage.member.test.tsx` (toggle → Save → `body.startsAway` true), `CreateGroupChatPage.steps.test.tsx` (toggle → `memberStartsAway` equality) — CI-only, green locally
- ✅ Manifest entry `ext.startsAway` landed (parity test green)

#### WP6: Final polish
- ✅ `dart format` clean on all touched Dart files (0 diffs, max 475 lines)
- ✅ `npm run lint` clean on all touched TypeScript files
- ✅ `docs/Rawhide.md` one `## Unreleased` bullet (already present)
- ✅ `docs/realism-engine.md` presence section (already present)
- ✅ All five desktop regression suites green:
  - Web settings test: 50/50 ✓
  - Helper tests: 4/4 ✓
  - Member editor widget test: 41/41 ✓
  - Seeding tests: 5/5 ✓
  - Parity test: 10/10 ✓

### Path-Complete Checklist

- [x] Desktop member editor: `EditCharacterRealismSection._build` (_edit(() => d.realismStartsAway = v))
- [x] Desktop member save: `EditCharacterCardWriter._writeExtensions` (startsAway: d.realismStartsAway)
- [x] Desktop relay: `realism_extensions_json.dart` (frontPorchFromFields / frontPorchToJson)
- [x] Desktop seeder: `group_member_starts_away.dart` (frontPorchExtensions?.startsAway)
- [x] Desktop wizard: `group_cast_steps.dart` (characterStartsAway map)
- [x] Web member editor: `RealismFormSection.tsx` (member-gated ToggleRow)
- [x] Web relay: `realism_extensions_json.dart` (boolMap, memberStartsAway)
- [x] Web wizard: `CreateGroupChatPage.tsx` (step-1 render + import)
- [x] Manifest: `group-card-field-manifest.json` (ext.startsAway entry)
- [x] Docs: `docs/Rawhide.md` + `docs/realism-engine.md`

### Intentional Presence-Behavior Changes

1. **Hold outranks the shift**: `heldAway = true` short-circuits before `derivePresence`'s `heldAway = false` at-work logic (WP2).
2. **Restore never re-seeds**: `startNewChat` does not re-seed `heldAway` from card if already held (WP3, seeding test "restore never re-seeds").

### Test-Integrity Edits

- [x] Existing test edits (approved-test-change): `group_settings_test.dart` (relay test), `CharacterEditPage.member.test.tsx` (member editor test), `CreateGroupChatPage.steps.test.tsx` (wizard test)
- [x] Manifest JSON edit: `group-card-field-manifest.json` (ext.startsAway entry)

### `## Hand-check` Section (UI PR)

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

### Poke Script

```bash
# Verify all tests pass
cd front-porch-AI
flutter test test/services/web/group_settings_test.dart
flutter test test/utils/group_member_extensions_test.dart
flutter test test/ui/pages/group_member_edits_save_test.dart
flutter test test/services/chat/starts_away_seeding_test.dart
dart test test/hygiene/group_card_field_parity_test.dart

# Verify formatting
dart format --output=none --set-exit-if-changed lib/ui/pages/edit_character_page/edit_character_realism_section.dart lib/ui/pages/edit_character_page/edit_character_save.dart lib/services/web/util/realism_extensions_json.dart
cd web_ui && npm run lint

# Verify docs
grep -A 1 "## Unreleased" docs/Rawhide.md | grep "Group members can start away"
grep -A 1 "Starts away" docs/realism-engine.md | head -5
```

### "I did not launch the app"

I did not launch the app to verify the feature manually. All verification was done through automated tests and code review.

### Next Steps

1. Commit the feature branch: `git commit -F <message-file>`
2. Push to origin: `git push -u origin feat/group-initial-presence`
3. Open PR to upstream `Rawhide` (github.com/linux4life1/front-porch-AI.git)
4. Re-fetch upstream and rebase (stale-base gate in `scripts/ci-local.sh`)
5. Add `approved-test-change` label to the PR
