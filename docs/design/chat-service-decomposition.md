# ChatService decomposition: statement of work

The ChatService shell (`lib/services/chat_service.dart`) is one 26,000-line
class spread across 77 `part` files. Every part is a public
`extension … on ChatService` that reads and writes a mixin of 154 private
fields (`ChatServiceFieldBag`, `lib/services/chat/chat_service_fields.dart`)
plus 74 more `late final` and plain fields on the class body.
The parts are the symptom. The shared private namespace is the problem: no
boundary exists between domains, so every change can touch every field.

This document is the plan to end that, split into work packages sized for
one agent session each. A separate agent verifies every package against the
protocol in "Verification" before it merges. Numbers below are from the
Rawhide tree at the time of writing; the ratchets, not this file, are the
source of truth once work starts.

## Starting state

| Measure | Value |
|---|---|
| `part` directives on the shell | 77 (75 extensions, 2 mixins) |
| Instance fields, bag plus shell | 228 (154 in the mixin, 74 on the class) |
| Public members declared in parts | 341 |
| Private members declared in parts | 438 |
| `notifyListeners()` calls in parts | 181 |
| `_build*` factories on the shell | 62 |
| Consumer files in `lib/` | 224 |
| Test files driving the real ChatService | 374 |
| Golden tests using `FakeChatService` | 94 |
| Integration suites | 42 |

The seam that already works is the scope pattern: `RealismScope` and
`StoryClockScope` hand a leaf class explicit inputs, and 186 leaf classes
under `lib/services/chat/` already live that way. This plan finishes that
job for the remaining state. It invents no new pattern.

## Target shape

ChatService stays the one `ChangeNotifier` that Provider, the web facades
and the 224 consumers see. Its constructor
`ChatService(kobold, personas, storage, worlds)` does not change. Every
public name a consumer calls today keeps working with no import change.

Internally ChatService becomes a thin facade over **doors**: real classes,
one per domain, each owning its own state. The field bag reaches zero
fields. The part list reaches zero parts.

**Shared state.** `ChatSessionState` (new, `lib/services/chat/session_state.dart`)
owns the four fields every domain reads: the message list, the current
session id, the active character and the group manager. ChatService owns one
instance and hands it to every door. `RealismScope` and `StoryClockScope`
take it instead of their closures once it exists.

**A door is:**

- a `ChangeNotifier` under `lib/services/chat/doors/<domain>/`, under 500
  lines, taking `ChatSessionState`, the services it needs and at most two
  callbacks (`saveChat`, and `notify` only if it is not itself a notifier)
  through its constructor;
- never holding a reference to `ChatService` (`grep ChatService` inside the
  door directory is empty);
- exposed on ChatService by one public getter;
- reachable by its old names through a **bridge**: a separate library
  `lib/services/chat/doors/<domain>/<domain>_api.dart` holding
  `extension … on ChatService` methods whose bodies only call that getter.
  The shell `export`s the bridge, so consumers keep their imports and names.
  A bridge touches no private state, so it is an extension in its own
  library, not a part, and the part ratchet does not count it.

**Members the golden fake overrides stay on the class.** The fake
(`test/golden/support/fakes.dart`) `implements ChatService`, so every new
class member needs an override there. A door getter is one override per
domain. A bridge member is an extension member, not an interface member,
and needs none. That is why bridges exist: the shell is at 499 lines and
cannot host 341 forwarders, and the fake cannot grow by 341 overrides.

**Notifications.** ChatService adds a listener to each door and re-emits,
as it already does for `GroupTurnManager`. One coalescing forwarder,
`ChatService._forwardDoorNotify`, so one turn does not fan out into many
rebuilds.

**Rules that hold in every package.**

- A door is never made by renaming a part. If a class takes a `ChatService`
  or reads a `_field` through the library, it is still a part.
- The old part is deleted in the same PR that lands its door. Each PR
  lowers `test/baselines/part_files.json` by exactly the parts it deleted
  and carries the `approved-test-change` label for that edit.
- The field count in `ChatServiceFieldBag` goes down in every package that
  moves state, and the ratchet from WP0 enforces it.
- The API manifest from WP0 does not change. A package that must change it
  says which name and why in the PR body.
- No existing test is edited except `fakes.dart` (the door getter) and the
  two baselines. If a test must change, the PR body gives the reason the
  old assertion is now false, per CLAUDE.md "Tests".
- Chat contracts in CLAUDE.md are the acceptance criteria. Path-complete
  work (Continue, regen, 1:1 and group, desktop and web) is stated in the
  PR body for WP5 onward.
- `dart format` only edited files. Zero analyzer warnings on touched Dart.

## Verification

The verifier runs this for every package before it merges. A package that
fails any line goes back with the failing line quoted.

1. `tools/preflight.sh` on the branch, then the full unit suite:
   `flutter test --concurrency=4 --exclude-tags golden`.
2. The integration suites the package names under "Done when", one file
   per run, on Linux.
3. `test/hygiene/part_file_ratchet_test.dart` passes and the diff to
   `test/baselines/part_files.json` lowers the ChatService count by exactly
   the number of parts the PR deletes.
4. The field-bag ratchet passes and the diff to its baseline is a decrease
   (or zero for WP0 and WP2 only).
5. The API manifest test passes with no baseline change, unless the PR
   body names the change.
6. `grep -rn "ChatService" lib/services/chat/doors/` returns only bridge
   files (`*_api.dart`).
7. `git diff --stat` against the base shows no edit to any file under
   `test/` other than `fakes.dart` and the two baselines, and no edit under
   `.github/`, `scripts/` or `analysis_options.yaml`.
8. Every new door file is under 500 lines; `god_file_ratchet_test` passes.
9. The web PWA is unaffected: the package changed nothing a user can see or
   configure. If it did, `web_ui/` changed in the same PR and
   `cd web_ui && npm run lint && npm test` passes.
10. The PR body carries the completion summary CLAUDE.md "Reporting" asks
    for: what was verified by which test, what was not, the path-complete
    matrix where chat state is in scope.

## Work packages

Each package is a stand-alone brief for a fresh session. Each lists the
exact parts it retires. Parts are named by their basename under
`lib/services/chat/`. Line counts are approximate.

### WP0. Guardrails (tests only)

Goal: pin the two things the suite does not pin today, so every later
package is provably surface-neutral and provably shrinks the god object.

Add two test files and two baselines. Model both on
`test/hygiene/part_file_ratchet_test.dart` and `test/helpers/source_ratchet.dart`.

- `test/hygiene/chat_service_field_bag_ratchet_test.dart` counts the
  instance fields declared in the `ChatServiceFieldBag` mixin and the
  `ChatService` class body. Baseline `test/baselines/chat_service_fields.json`
  records the count. The count may only go down; a decrease must lower the
  baseline in the same change. `FPAI_TIGHTEN_BASELINES=1` lowers it.
  Landed at 228 on Rawhide.
- `test/hygiene/chat_service_api_manifest_test.dart` lists every public
  member name reachable on a `ChatService` value: class members, mixin
  members, and members of every public `extension … on ChatService` in the
  shell library and in any library the shell exports. Baseline
  `test/baselines/chat_service_api.json` is the sorted list. Any
  difference, in either direction, fails with the names.

Done when: both tests pass on the untouched tree, both fail when a public
member is removed or a field is added (prove it in the PR body with the
one-line edit you reverted), and `tools/preflight.sh` is green. No
`approved-test-change` label needed: new files only.

### WP1. Shared session state

Goal: create `ChatSessionState` and move the four core fields into it, so
every later door has something to take.

- New `lib/services/chat/session_state.dart`: a plain class owning
  `messages` (the mutable list), `currentSessionId`, `activeCharacter` and
  `groupManager`. No `ChangeNotifier`; ChatService still notifies.
- ChatService owns one `final _session = ChatSessionState()`.
- Mechanical rename inside the library: `_messages` → `_session.messages`
  (419 sites), `_activeCharacter` → `_session.activeCharacter` (266),
  `_currentSessionId` → `_session.currentSessionId` (199),
  `_groupManager` → `_session.groupManager` (57). Delete the four fields
  from the bag.
- `RealismScope` and `StoryClockScope` gain a `session` input and drop the
  closures it replaces (`messages`, `activeCharacter`, `activeGroup`,
  `groupCharacters`). Their leaf consumers read through it.

Done when: field bag baseline drops by four, part count unchanged, API
manifest unchanged, full unit suite green, and these suites pass:
`integration_test/app_smoke_test.dart`, `chat_switch_smoke_test.dart`,
`group_smoke_test.dart`, `regen_feelings_cadence_test.dart`.

Must not: change any behaviour. This package is a rename. If a rename
exposes a bug, note it in the PR body and leave it.

### WP2. Media and quick actions door

Goal: prove the door mechanism on the least coupled domain.

Parts retired (4, ~750 lines): `chat_service_images`, `chat_service_photo`,
`chat_service_web_search`, `chat_service_actions`.

- Door `lib/services/chat/doors/media/media_door.dart` for generated-image
  and photo messages and web-search dispatch; door
  `lib/services/chat/doors/actions/actions_door.dart` for action
  suggestions (the anchor rule from #329 moves with its fields).
- Fields that move: the suggested-actions trio, the pending forced
  web/wiki queries, and whatever the image and photo parts own in the bag.
- Bridges `media_api.dart` and `actions_api.dart`, exported from the shell.
- `addGeneratedImageMessage`, `suggestedActions` and
  `isGeneratingActions` are fake-overridden class members. They stay on the
  class as one-line forwarders to the door.
- `FakeChatService` gains `mediaDoor` and `actionsDoor` getters returning
  fakes under `test/golden/support/`.
- Add `_forwardDoorNotify` on the shell and use it for both doors.

Done when: part baseline 77 → 73, field bag down, manifest unchanged,
`integration_test/suggested_action_composer_test.dart` and
`message_actions_test.dart` pass. The 42 test files that mention generated
images, photos or web search pass unedited.

### WP3. Import and export door

Parts retired (7, ~1,580 lines): `chat_service_sillytavern`,
`chat_service_import_seed`, `chat_service_import_walk`,
`chat_service_chat_package`, `chat_service_chat_package_import`,
`chat_service_enhance_chats`, `chat_service_package_extras`.

- Door `lib/services/chat/doors/transfer/` with `ChatImporter` (SillyTavern,
  package import, the walk) and `ChatPackager` (export, extras, enhance).
- `import_seed` touches 32 fields because it seeds clock and Realism scalars
  into a freshly imported chat. Those writes go through the session store
  and Realism doors once they exist; until WP7 and WP9 land, the importer
  takes a `seedScalars` callback that ChatService implements. Name that
  callback in the PR body as debt WP7 retires.
- `isImporting` is a class member read by the composer. It stays as a
  forwarder.

Done when: part baseline → 66, `integration_test/porch_byaf_import_dialog_test.dart`,
`lorebook_import_test.dart` and `backup_restore_test.dart` pass, and the 25
test files that mention import or packages pass unedited.

### WP4. Objectives door

Parts retired (4, ~1,500 lines): `chat_service_objectives`,
`chat_service_objective_tasks`, `chat_service_objective_completion`,
`chat_service_speaker_objectives`.

- Door `lib/services/chat/doors/objectives/objectives_door.dart` owning the
  active list, the tally, the completion flag and the sidebar
  task-generation prefs.
- Contract: `objectivesActive` is a live AND of the per-chat switch and
  `realismSettings.objectivesEnabled`, read every turn. It stays a class
  getter and still reads live.
- Fake-overridden class members stay as forwarders: `primaryObjective`,
  `secondaryObjectives`, `objectiveTally`, `isCheckingCompletion`,
  `skipObjectiveCheck`, `getObjectivesForGroupCharacter`,
  `getActiveObjectivesFor`.
- Keys `character_id` by `stableGroupId`, never `characters.id`; the door
  takes `characterIdFor` from the session state.

Done when: part baseline → 62, the 86 objective test files pass unedited,
`integration_test/group_realism_wiring_test.dart` passes.

### WP5. Message operations door

Parts retired (6, ~2,650 lines): `chat_service_message_ops`,
`chat_service_regen_revert`, `chat_service_reprocess`,
`chat_service_reprocess_choice`, `chat_service_variants`,
`chat_service_impersonate`.

- Door `lib/services/chat/doors/edits/` with `MessageEditor` (edit, delete,
  tail delete), `RegenController` (regen, revert, swipe variants, token
  alternatives), `Reprocessor` (manual Needs and Feelings reprocess) and
  `Impersonator`.
- Path-complete: regen rewinds from `story_clock_before`; delete rolls
  Needs back; swipe keeps Journal and Growth per chat; 1:1 and group both
  restore by message speaker id. Load the `path-complete-chat` skill and
  put the matrix in the PR body.
- `editMessage` and `regenerableHostBelowGuestsIndex` are class members.
  They stay as forwarders.

Done when: part baseline → 56, the 186 test files that mention regen,
swipe, reprocess or impersonate pass unedited, and these suites pass:
`integration_test/regen_shortcut_test.dart`, `swipe_fork_cancel_test.dart`,
`needs_reprocess_test.dart`, `message_actions_test.dart`.

### WP6. Cast door

Parts retired (9, ~2,900 lines): `chat_service_cast`,
`chat_service_cast_shrink`, `chat_service_scene_guest`,
`chat_service_guest_flow`, `chat_service_greeting`,
`chat_service_greeting_seed`, `chat_service_away_pulse`,
`chat_service_idle_autonomous`, `chat_service_group_lite`.

- Door `lib/services/chat/doors/cast/` with `CastController` (roster,
  join, exit, collapse to 1:1, 1:1 to group carry), `GuestFlow` (Scene
  Guest lifecycle, detected-cast popup, minting), `GreetingPicker`,
  `AwayPulse` and `IdleAutonomy`.
- `cast`, `greetingIndex`, `isTurnBusy` and `callMode` are class members
  and stay as forwarders. `isTurnBusy` is read by the window cast edits;
  keep its predicate identical to the one `sendMessage` uses.
- A `/join`ed guest in a 1:1 reads as a guest on both rosters (#648).

Done when: part baseline → 47, the 180 test files that mention guests,
greetings, idle or the away pulse pass unedited, and
`integration_test/group_smoke_test.dart`, `place_mint_journey_test.dart`
and `chat_switch_smoke_test.dart` pass.

### WP7. Session store door

Parts retired (9, ~3,100 lines): `chat_service_session_state`,
`chat_service_session_state_save`, `chat_service_session_load`,
`chat_service_session_hydrate`, `chat_service_session_window`,
`chat_service_session_manage`, `chat_service_session_fork`,
`chat_service_session_new_chat_prep`, and the
`chat_service_today_sentence` mixin.

- Door `lib/services/chat/doors/session/` with `SessionStore` (load, save,
  scalar capture and restore), `SessionHydrator` (tail-first hydrate and
  chunked backfill), `SessionForker`, `NewChatPrep` and the today sentence.
- Owns summary, author note, session gen settings and theme overrides.
  `sessionGenSettings`, `sessionThemeOverrides`, `summary*`, `authorNote*`
  stay as class forwarders.
- Retires the WP3 `seedScalars` debt: the importer now calls the store.
- Contracts: `captureCadenceAndFeelings` and `restoreFromMessageState`
  carry every non-scalar input; regen with the same inputs reproduces the
  same deltas; every conversation start path seeds Chaos
  (`grep seedFromGroupOrExt`).

Done when: part baseline → 38, the 78 test files that mention fork, load,
hydrate or new chat pass unedited, and `integration_test/swipe_fork_cancel_test.dart`,
`chat_find_test.dart`, `story_time_test.dart` and
`regen_feelings_cadence_test.dart` pass.

### WP8. Entry and group roster door

Parts retired (7, ~2,350 lines): `chat_service_chat_entry`,
`chat_service_group_entry`, `chat_service_group_store_migrate`,
`chat_service_group_read`, `chat_service_group_settings`,
`chat_service_group_membership`, `chat_service_group_members`.

- Door `lib/services/chat/doors/entry/` with `ChatEntry` (open a 1:1),
  `GroupEntry` (open a group), `GroupRoster` (membership, member switches,
  store migration).
- These two parts touch the most fields (50 and 43). By this package the
  fields they touched belong to doors from WP2 to WP7, so entry becomes a
  sequence of door calls. If a field is still in the bag, that is the
  finding: move it to its owner in this PR and say so.
- Group restore keys by message speaker id; `_saveScalarsIntoGroupRealism`
  persists group state. `setMemberAfterglowEnabled` is a class member and
  stays a forwarder.
- 1:1 and group: a character's observable Realism and Needs results match
  in both modes.

Done when: part baseline → 31, the 124 test files that mention group entry
or membership pass unedited, and `integration_test/group_smoke_test.dart`,
`group_realism_wiring_test.dart`, `world_starting_place_test.dart` and
`realism_off_test.dart` pass.

### WP9a. Realism graph

Parts retired (7, ~2,900 lines): `chat_service_wiring_realism`,
`chat_service_wiring_evals`, `chat_service_wiring_evals_judges`,
`chat_service_wiring_memory`, `chat_service_wiring_injection`,
`chat_service_wiring_injection_leaves`, `chat_service_wiring_mint`.

- `lib/services/chat/doors/realism/realism_graph.dart` builds, once, every
  object the 62 `_build*` factories build today, from `ChatSessionState`,
  the storage service and the door getters. The shell's `late final`
  fields become one `late final _realism = RealismGraph(...)` and the
  public getters (`relationshipService`, `timeService`, `needsSimulation`,
  `journalStore`, `pocketsFor`, `milestoneFeed` and the rest) forward to it.
- Eval transport contract: native tool call first, then the text floor,
  no GBNF on the floor, the judges share `kJudgeEvalTools`.
- Needs: one gate, `NeedsPass.active`, read live by every pass.

Done when: part baseline → 24, `test/hygiene/needs_gate_ratchet_test.dart`,
`clock_*_ratchet_test.dart` and `test/services/chat/one_shot_parity_test.dart`
pass unedited, and `integration_test/realism_off_test.dart`,
`journal_review_test.dart`, `growth_rings_test.dart` and
`climax_refractory_test.dart` pass.

### WP9b. Controls and lanes

Parts retired (5, ~1,500 lines): `chat_service_controls`,
`chat_service_accessors_living`, `chat_service_planner_resolve`,
`chat_service_llm_lanes`, `chat_service_defaults`.

- `lib/services/chat/doors/controls/controls_door.dart` for the runtime
  switches (Realism, Needs, Chaos, passage of time, NSFW) and the permission
  watch and start queue. `setPassageOfTimeEnabled`, `setNeedsSimEnabled`,
  `setAfterglowEnabled`, `realismEnabled`, `realismChatSwitch` stay as
  class forwarders.
- `lib/services/chat/llm_lanes.dart` for studio-wizard model lanes.
- `chat_service_defaults` is top-level constants: move to
  `lib/services/chat/chat_defaults.dart` and import it.
- Living accessors (weather, ambitions) forward to the realism graph.
- Clock: `_clockRunning` is Porch Life `passageOfTimeDefault` live. Keep it
  a live read.

Done when: part baseline → 19, the settings parity manifest test passes,
`integration_test/settings_persistence_test.dart` and
`story_time_test.dart` pass.

### WP10a. Prompt assembler

Parts retired (8, ~2,500 lines): `chat_service_generation_blocks`,
`chat_service_generation_plan`, `chat_service_generation_plan_register`,
`chat_service_generation_rag`, `chat_service_generation_request`,
`chat_service_prompt_blocks`, `chat_service_context_budget`,
`chat_service_history`.

- `lib/services/chat/doors/turn/prompt_assembler.dart` builds the request
  from the session state, the realism graph's injections and the history
  window. `ContextBudget` becomes its own class with the five budget getters
  forwarded from the shell.
- The chunked eviction anchor (`_HistoryAnchor`) moves with history; it
  protects the local backend's prefix cache and must keep the same chunk
  rule.
- The 21 test files that pin prompt sections (`lastPromptSections`,
  prompt blocks) are the acceptance test. They pass unedited.

Done when: part baseline → 11, those 21 files pass, and
`integration_test/lorebook_chat_test.dart`, `continue_path_test.dart` and
`app_smoke_test.dart` pass.

### WP10b. Turn engine

Parts retired (6, ~2,050 lines): `chat_service_generation`,
`chat_service_generation_entry`, `chat_service_generation_stream`,
`chat_service_generation_stream_accessors`,
`chat_service_generation_postgen`, `chat_service_generation_postgen_engine`.

- `lib/services/chat/doors/turn/turn_engine.dart` runs one generation:
  stream, progress, post-generation passes. `TurnProgress` owns
  `isGenerating`, progress, token counts, phase and prefill timing; the
  shell forwards those getters. `isGenerating` keeps its narrow meaning
  (token streaming only, see the shell comment).
- Continue is not regen: no clock tick, scores only `newPart`, keeps
  `pockets_before`, does not consume one-shots, finalizes pre-continue plus
  new body. Post-gen passes (posture, climax, pockets) each keep their own
  gate; a fused reply-facts call is transport only.
- Path-complete matrix in the PR body: Continue, regen, 1:1, group,
  desktop, web.

Done when: part baseline → 5, `test/services/chat/one_shot_parity_test.dart`,
`pockets_rewind_test.dart` and the clock ratchets pass unedited, and
`integration_test/continue_path_test.dart`, `regen_feelings_cadence_test.dart`,
`climax_refractory_test.dart` and `group_smoke_test.dart` pass.

### WP10c. Send spine

Parts retired (3, ~1,460 lines): `chat_service_send`,
`chat_service_send_handoff`, `chat_service_turn_flow`.

- `lib/services/chat/doors/turn/send_spine.dart` owns `sendMessage`, the
  hand-off to the engine, group speaker picking, TTS-paced auto-play, the
  Chance Time reveal and background RAG embedding.
- The composer's guard uses the same predicate as `sendMessage`. The
  predicate lives in one place the composer and the spine both read.
- `sendMessage` is an extension member today, so it moves to the bridge
  unchanged. The fake does not override it and must not start to.

Done when: part baseline → 2, the 177 test files that mention send,
Continue or post-gen pass unedited, and `integration_test/app_smoke_test.dart`,
`group_smoke_test.dart`, `web_server_test.dart` and
`suggested_action_composer_test.dart` pass. Web E2E runs green.

### WP11. Close-out

Parts retired (2): `chat_service_accessors`, `chat_service_fields`.

- Whatever `chat_service_accessors` still holds (init, dispose, listener
  wiring) moves onto the shell or into the door that owns it. The shell
  stays under 500 lines; if it does not, a door is taking too little.
- The field bag is empty. Delete the mixin and `with ChatServiceFieldBag`.
- Delete the ChatService entry from `test/baselines/part_files.json` and
  from `_exceptions` in `test/hygiene/part_file_ratchet_test.dart`, with the
  `approved-test-change` label. From then on the ratchet treats the shell
  like any other library.
- Delete the field-bag ratchet from WP0 and its baseline; it has nothing
  left to count. Keep the API manifest.
- Update CLAUDE.md "Layout" and "Size law": the ChatService shell no longer
  keeps parts. Update `AGENTS.md` to agree.

Done when: part count 0, full unit suite, all 42 integration suites on
Linux, web tests and web E2E green.

## Sequencing

WP0 and WP1 are serial and first. WP2, WP3 and WP4 are independent of each
other after WP1 and may run in parallel on separate branches off Rawhide.
WP5 and WP6 depend on WP2 to WP4 being merged. WP7 depends on WP5 and WP6.
WP8 depends on WP7. WP9a and WP9b depend on WP8. WP10a, WP10b and WP10c are
serial after WP9b. WP11 is last.

Each package is one PR to Rawhide, opened as a draft, with the
`approved-test-change` label applied by the maintainer for the baseline
edit. A package that cannot finish without leaving a part half-moved stops
and says so; it does not land a door that still reads the bag.

## What the suite does and does not catch

The behaviour net is dense: 374 test files drive the real ChatService, 457
files sit under `test/services/chat/`, 42 integration suites run the real
app, 21 files pin prompt assembly, and only 4 tests need a live model.
Every chat contract in CLAUDE.md is pinned by a named test. A door that
changes behaviour in any covered path fails a test that was not edited.

Two gaps exist today and WP0 closes them: nothing pins the public API
shape, and nothing pins the field count. Two gaps remain after WP0 and the
verifier covers them by hand: the 94 golden tests use the fake, so they
are blind to the real service's listener cadence, and a behaviour no test
exercises can move silently. The verifier's line 9 (nothing user-visible
changed, or `web_ui/` moved with it) and the integration suites named per
package are the backstop for both.
