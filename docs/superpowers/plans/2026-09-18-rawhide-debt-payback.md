# Rawhide debt payback

> **Status (updated as the work lands).** The plan below is the inventory and the
> sequence. What has actually shipped on this branch:
>
> | Task | State | Commit |
> | --- | --- | --- |
> | T1 Drift managers off + generated-size ratchet | done | `build: stop generating Drift table managers nobody calls` |
> | T2 two dead files + barrel exports | done | `refactor: delete two files nothing ever called` |
> | T3 dead declarations (21, not 16 — 5 were stranded by the first 16) | done | `refactor: delete 21 declarations with no callers anywhere` |
> | T4 orphan web-search round | done | `refactor: delete the second web-search round-trip` |
> | T5 three decoration tests | done | `test: make three guards depend on the code they name` |
> | T6 five stale notes | done | `docs: correct five notes that no longer match the code` |
> | T7 dead CSS + `styles.css` split (19 slices) | done | `style(web): drop twelve dead rules, then split the stylesheet by surface` |
> | T8 think-strip | done | `refactor: one think-strip per contract, not ten copies of three` |
> | T9 lorebook import once | done | `refactor(lorebook): import takes its post-decode steps once` |
> | T10 receipt column once | done | `fix(journal): the same receipt column read three ways, now read once` |
> | T11 settings facade split | done | `refactor(web): split the settings facade into its read and write halves` |
> | T12 dual tool probes | done (documented, not merged) | `docs: the two tool probes are two layers, not one duplicated` |
> | S1.1 chat tools facade | done | `refactor(web): split the chat tools facade by tool domain` |
> | S1.2 stoop upload wizard | done | `refactor(stoop): split the share wizard into chrome, steps, and publishing` |
> | S1.3 group-create wizard | done | `refactor(ui): split group-create into roster, generate, and commit` |
> | S1.4 creator state | done | `refactor(creator): split prefs and model loading off the field bag` |
> | S1.8 realism form | done | `refactor(ui): split the Realism form into engine, porch, and controls` |
> | S1.15 growth panel | done | `refactor(ui): split Growth Rings into cards, actions, and the editor` |
> | S1.6 stoop comments | done | `refactor(stoop): split card discussion into actions and views` |
> | S1.9 hardware detection | done | `refactor(hardware): split detection by platform` |
> | S1.14 pockets | done | `refactor(pockets): separate the record, the grammar, the matching, the applier` |
> | S1.16 Chance Time overlay | done | `refactor(ui): split Chance Time into shell, views, and painters` |
> | CI follow-up (notify / GrowthPanel statics / theme-keep / io-ok) | done | `fix: analyzer, theme-lint, and io-lint after the S1 splits` |
> | S1.5 ChatPage.tsx | done | `refactor(web): split ChatPage into session, send, and overlays` |
> | S1.7 chat_service.dart shell | done | `refactor(chat): move ChatService private fields onto a mixin` |
> | S1.10 time_service.dart | done | `refactor(chat): split TimeService into eval and apply` |
> | S1.11 web_server_host.dart | done | `refactor(web): split the host into streams and wiring` |
> | S1.12 kobold_service.dart | done | `refactor(kobold): split admin extras off generate/abort` |
> | S1.13 chat_page.dart | done | `refactor(ui): split ChatPage overlays and app-bar host` |
> | S1.17 open_router_service.dart | done | `refactor(remote): split OpenRouter tools and catalog off generate` |
> | S1.18 ChatTools.tsx | done | `refactor(web): split ChatTools into memory, realism, and objectives` |
> | S1.19 llm_eval_engine.dart | done | `refactor(chat): split eval extract and think-strip off fire` |
> | S2 chat_service_accessors.dart | done | `refactor(chat): split today-sentence and planner off accessors` |
> | S2 needs_impact_evaluator.dart | done | `refactor(chat): split needs bound and activity table off fire` |
> | S2 chat_service_session_manage.dart | done | `refactor(chat): split fork and rename off new-chat seed` |
> | S2 chat_command_handler.dart | done | `refactor(chat): split guest mint off slash parse` |
> | S2 realism_verification.dart | done | `refactor(chat): split verification rules and critique off fire` |
> | S2 setup_step.dart | done | `refactor(creator): split Extra Settings and the status dot off the form` |
> | S2 chat_service_reprocess.dart | done | `refactor(chat): split regen revert and swipe-merge off the hold` |
> | S2 chat_facade.dart | done | `refactor(web): split swipe and history off chat send-load` |
> | S2 chat_service_session_load.dart | done | `refactor(chat): split session hydrate off last-session and the list` |
> | S2 chat_service_objectives.dart | done | `refactor(chat): split objective tasks and completion off inject` |
> | S2 update_service.dart | done | `refactor(update): split download and install off the GitHub check` |
> | S2 group_member_card.dart | done | `refactor(ui): split group-member menus and views off the card` |
> | S2 data_bank_dialog.dart | done | `refactor(ui): split Data Bank editor and import off the list` |
> | S2 world_repository.dart | done | `refactor(worlds): split chat attach and biome spans off CRUD` |
> | S2 database_cleanup.dart | done | `refactor(db): split orphan apply off the read-only scan` |
> | S2 edit_character_page.dart | done | `refactor(ui): split the character-editor tab host off the field bag` |
> | S2 memory_service.dart | done | `refactor(rag): split retrieve scoring off embed and store` |
> | S2 stoop_browse_view.dart | done | `refactor(stoop): split the browse grid off search and load` |
> | S2 chat_service_wiring_evals.dart | done | `refactor(chat): split judge builders off the eval engine and transport` |
> | S2 generate_kcpps_dialog.dart | done | `refactor(ui): split kcpps generate off the form` |
> | S2 model_manager_page.dart | done | `refactor(ui): split HuggingFace download off the local list` |
> | S2 chat_service_wiring_injection.dart | done | `refactor(chat): split injection leaf builders off lore and world helpers` |
> | S2 rag_injection.dart | done | `refactor(chat): split RAG receipt and cover-drop off the memories block` |
> | S2 chat_service_send.dart | done | `refactor(chat): split send decay and generate handoff off capture` |
> | S2 stoop_card_detail_page.dart | done | `refactor(stoop): split the detail body off the panel and break the creator cycle` |
> | S2 character_facade.dart | done | `refactor(web): split character import off the read facade` |
> | S2 image_studio.dart | done | `refactor(ui): split Image Studio subject pick off the canvas` |
> | S2 growth_store.dart | done | `refactor(growth): split ring writes off the cursor cache` |
> | S2 user_persona_service.dart | done | `refactor(persona): split the record and file import off the store` |
> | S2 chat_service_pockets.dart | done | `refactor(pockets): split the post-gen pass off intro and persist` |
> | S2 settings_facade.dart | done | already split in T11 (213 / 149 / 299) — no further cut |
> | S2 useLibrary.ts | done | `refactor(web): split library folder and card writes off load` |
> | S2 backend_manager.dart | done | `refactor(backend): split KoboldCpp download off version check` |
> | S2 chat_service_cast.dart | done | `refactor(chat): split group collapse and host carry off exit` |
> | S2 home_page_dialogs.dart | done | `refactor(ui): split character import off delete and duplicate` |
> | S2 home_page_chrome.dart | done | `refactor(ui): split open-chat and menus off the mode toggle` |
> | S2 chat_service_generation_postgen.dart | done | `refactor(chat): split post-gen engine bookkeeping off finalize` |
> | S2 StoopAccountPage.tsx | done | `refactor(stoop): split uploads and following off the account page` |
> | S2 settings_page.advanced.dart | done | `refactor(ui): split the web-server section off storage and cleanup` |
> | S2 chat_service_session_state.dart | done | `refactor(chat): split session persist off guest and group hydrate` |
> | S2 chat_service_group_membership.dart | done | `refactor(chat): split live members off the 1:1 group fork` |
> | S2 image_gen_service.backends.dart | done | `refactor(image): split generators off disk save` |
> | S2 chat_service_chat_package.dart | done | `refactor(chat): split fpchat import off export` |
> | S2 styled_text_controller.dart | done | `refactor(ui): split tokenizer and presets off the styled controller` |
> | S2 character_card_grid.dart | done | `refactor(ui): split grid cells off the home toolbar chrome` |
> | S2 world_facade.dart | done | `refactor(web): split world and lorebook import off CRUD` |
> | S2 remaining / S3 | done | last S2 row was world_facade |
> | residual accessors living | done | `refactor(chat): split living-time and cast off accessor setters` |
> | residual chat_facade state | done | `refactor(web): split chat state payload off send and load` |
> | residual memory embed | done | `refactor(rag): split window embed insert off retrieve` |
> | residual world purge | done | `refactor(worlds): split character-clone purge off CRUD` |
> | residual pass_support fire | done | `refactor(chat): split structured-eval fire off the transport probe` |
> | residual keep census | done | every remaining production file over 500 is ONE, LIST, or the ChatService shell |
>
> **Corrections the work forced on this plan** (the inventory was right about
> what to look at, wrong about two conclusions):
>
> - **T8 was not five copies of one contract.** `StoryJson.stripThinkTags` is
>   JSON-anchored: on an unclosed tag the shared helper deletes to end-of-string,
>   which would delete the JSON the story pipeline came for.
>   `char_macro.stripThinkBlocks` matches misspelled tags because chargen runs
>   hot. Both are documented in place as deliberate. `image_prompt_builder` and
>   `regen_critique_injection` are still foldable but each carries a small
>   unpinned behaviour delta, so each needs its own guard.
> - **T5's C26 could not be done as written.** `realism_parity_test` cannot drive
>   ChatService's `_loadGroupRealismIntoScalars` / `_saveScalarsIntoGroupRealism`
>   — they are private to a part-file library, and inventing a public hook for a
>   test would be the shim this work is removing. Its overclaiming header was
>   corrected instead, naming `integration_test/group_smoke_test.dart` as the
>   owner of that path.
> - **Two commits need the `approved-test-change` label** (T4, T5): they edit
>   existing test files, which `test-integrity.yml` blocks by design.

> The text below was written before any of it shipped, so it reads as a plan.
> Treat the status table above as what is true.

**Goal:** Pay back size, spaghetti, and leftover cruft on `Rawhide` after squash `c11669bc` (PR #262) in a sequence of later PRs. Each later PR must leave the app buildable and the suite honest.

**Architecture:** Front Porch AI is a Flutter desktop app plus a React PWA (`web_ui/`) served by the Dart host. Chat orchestration is a `part`-file `ChatService` (65 `part 'chat/…'` directives) over shared leaves. Persistence is Drift / SQLite (`schemaVersion` 52). Web talks to facades and a `/api/stoop/*` relay, not the Stoop backend directly.

**Tech stack:** Dart 3.10 / Flutter, Provider, Drift 2.34, React / Vite PWA. Formatter is the official `dart format` (Dart 3.7+ tall style). Analyzer is `flutter analyze --no-fatal-warnings --no-fatal-infos`.

**Bar for this inventory:** 500 lines, not the old 999-line ratchet. The CI god-file ratchet at 1,000 lines with empty `test/baselines/god_files.json` stays. This plan uses 500 as the *split* bar.

---

## How this was measured

Tip: `c11669bc` on `Rawhide` (PR #262 squash). Counts are `wc -l` / Python line counts of the file on disk. No invented numbers.

| What | Count |
| --- | ---: |
| Source files scanned (`.dart` `.ts` `.tsx` `.js` `.jsx` `.css` under `lib/`, `test/`, `integration_test/`, `web_ui/`, `tools/`; skip `node_modules`, `.dart_tool`, `build`) | 2,242 |
| Files over 500 lines (this inventory) | **160** |
| of those in `lib/` | 105 |
| of those in `test/` | 44 |
| of those in `web_ui/` | 9 |
| of those in `integration_test/` | 2 |
| of those in `tools/` | 0 |
| Verdict SEVERAL (split targets) | 66 |
| Verdict ONE (one job, long; do not split for size) | 40 |
| Verdict LIST (generated / test suite / ladder / table; do not split) | 54 |
| Files over 999 lines | 9 |
| `lib/` Dart files / lines | 1,187 / 327,708 |
| same, excluding `*.g.dart` | 1,183 / 302,816 |
| Generated `*.g.dart` files / lines | 4 / 24,892 |
| `lib/database/database.g.dart` | 24,343 |
| Unused Drift manager tail (`$$*FilterComposer` onward, line 16,692–24,343) | 7,652 (31%) |
| Barrel files (directory named `dir/dir.dart`) | 36 |
| `ChatService` `part 'chat/…'` directives | 65 |
| `test(` calls under `test/` + `integration_test/` | 5,128 |
| Cruft items after PR #262 (numbered below) | **40** |

`web_ui/package-lock.json` is 7,283 lines and was excluded (lockfile, not source).

Verdict rules:

- **LIST** — generated code, a golden/fixture, a migration ladder, a lookup table, or a long test file that is one suite. Long because it is a list. Not a split target.
- **ONE** — one responsibility. Over 500 because the domain is large. Do not split just to hit 500.
- **SEVERAL** — mixed responsibilities in one file. Split target.

`database.g.dart` is LIST (generated) **and** a real task: turn off unused manager generation and ratchet the generated size. That is codegen, not a hand split.

---

## Global constraints (every later task)

These bind every PR this plan sequences. A task that violates one is incomplete.

1. **DRY.** One contract, one implementation. Do not add a second helper, a shim beside the live path, or a test that reimplements the product. If two call sites do the same job, they call the same function.
2. **Readable Dart.** A reader who was not in the room must be able to follow the file. Prefer boring names and short functions over cleverness.
3. **Limited comments.** Comment only where the next reader would otherwise do the wrong thing (a load-bearing default, a twin path, a trap that already shipped). Do not narrate the code.
4. **Tall-style Dart via the official formatter.** End every Dart task with `dart format path/to/that_file.dart` on the files that task already edited. Never `dart format .`. Never format a directory. Never format generated `*.g.dart`. Never format an existing test you did not otherwise change. CI already runs `dart format --set-exit-if-changed` on touched files (`.github/workflows/ci.yml`). Language version stays `sdk: ^3.10.8`.
5. **Zero analyzer issues.** `flutter analyze --no-fatal-warnings --no-fatal-infos` must be clean on the change — no warnings and no lints, not only no errors. `analysis_options.yaml` already excludes `**/*.g.dart`.

Also still in force from repo law:

- Web / desktop parity for anything user-visible.
- Realism / Needs 1:1 ↔ group parity.
- Path-complete chat work when a task touches generation, Continue, regen / swipe / delete, Realism, Needs, Journal, Growth, Pockets, RAG, or group orchestration. Fill `docs/design/path-complete-chat-work.md`.
- Barrel imports on every Dart file you touch.
- `AppColors` / porch amber for new or refactored UI.
- No file under `lib/` may reach 1,000 lines (god-file ratchet). New and extracted Dart files target under 500.
- Editing or deleting an existing test, golden, baseline, workflow, or `analysis_options.yaml` needs the maintainer `approved-test-change` label. Adding a *new* test file does not.
- Do not edit `pubspec.yaml` version. Do not touch `lib/database/database.dart` table list or the `onUpgrade` ladder bodies without a dedicated schema discussion.
- Author commits as the repo account. Public text (this plan, PR title, PR body) carries no personal name.

---

## What PR #262 already did (do not undo)

Squash `c11669bc`: unused Dart files, leftover storage shims, decoration tests that stayed green without the product, `.recovery/` snapshots, agent progress notes, unused screenshots / DMG art. Restored call-site pins stay. Speech contract in `lib/utils/think_tags.dart` `resolveMouthSpeech`:

- A **closed** think-only body is spoken (lifted onto the bubble).
- An **unclosed** cut-off is closed in place and stays off the bubble.

Pins this plan must not delete or weaken:

- `test/services/chat/pre_eval_mouth_speech_test.dart` (added by #262).
- `test/services/chat/wardrobe_message_zero_test.dart` hide-not-erase pin (open dressed, then switch off, `pocketsFor` is null).
- The restored call-site pins #262 put back (source-reading tests that fail if the live line dies). Do not treat those as decoration.
- `cropFillR` in `lib/utils/crop_geometry.dart` — `test/ui/dialogs/image_crop_dialog_test.dart` decodes a real PNG.
- `CreatorEngine` — production callers in `character_creator_page.dart` and `review_step.dart`.
- `WorkerBackendStorage` — extension members used by the worker backend UI.
- Linux-gated goldens (`@TestOn('linux')`, `golden` tag).
- `objectivesActive` live AND (`_objectivesEnabled && realismSettings.objectivesEnabled`) in `chat_service_accessors.dart`. Two-of-four seed sites are deliberate, not a bug.
- Chaos default seeded in **four** entry paths: `chat_service_chat_entry.dart`, `chat_service_group_entry.dart`, `chat_service_session_manage.dart`, `chat_service_import_seed.dart`. Wire fewer and the switch is silently 1:1-only.

---

## Inventory A — every source file over 500 lines (160)

Ranked by line count. `package-lock.json` excluded.

| # | Lines | Path | Verdict | What it does | Split? |
| ---: | ---: | --- | --- | --- | --- |
| 1 | 24343 | `lib/database/database.g.dart` | LIST | Drift-generated table companions, mappers, and (from line 16692) unused table-manager API for 21 tables. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 2 | 3129 | `test/services/chat/gist_first_recall_locks_test.dart` | LIST | RAG gist-first recall lock suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 3 | 2960 | `web_ui/src/styles.css` | SEVERAL | Single stylesheet for the PWA: 58 visual sections, including 12 unused class rules. | Split — mixed responsibilities. |
| 4 | 1823 | `test/services/chat/greeting_opening_seed_test.dart` | LIST | Greeting / opening-seed suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 5 | 1781 | `test/services/chat/remember_vs_regurgitate_test.dart` | LIST | RAG remember-vs-regurgitate suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 6 | 1527 | `test/services/chat/rag_injection_test.dart` | LIST | RAG injection suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 7 | 1218 | `test/services/chat/needs_impact_evaluator_test.dart` | LIST | Needs-impact evaluator suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 8 | 1108 | `test/services/backporch/stoop_comment_gate_test.dart` | LIST | Stoop comment-gate suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 9 | 1056 | `test/services/chat/journal_test.dart` | LIST | Journal maintenance / apply suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 10 | 995 | `lib/services/web/facade/chat_tools_facade.dart` | SEVERAL | Web relay for every chat-sidebar tool: memory, journal, growth, chaos, NSFW, clock, objectives, pockets, weather, director. | Split — mixed responsibilities. |
| 11 | 990 | `lib/ui/pages/repository/stoop_upload_page.dart` | SEVERAL | Stoop share wizard: pick / details / content / review plus character, group, and world publish. | Split — mixed responsibilities. |
| 12 | 988 | `lib/ui/pages/create_group_chat_page.dart` | SEVERAL | Group-chat creator wizard: roster, settings, realism seed, and create. | Split — mixed responsibilities. |
| 13 | 987 | `lib/ui/character_creator/creator_state.dart` | SEVERAL | Creator wizard state: prefs, load/save, step machine, generation, and review fields. | Split — mixed responsibilities. |
| 14 | 982 | `test/services/storage_service_test.dart` | LIST | StorageService suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 15 | 978 | `web_ui/src/pages/ChatPage.tsx` | SEVERAL | Web chat page: socket, send, history, overlays, theme, and composer wiring. | Split — mixed responsibilities. |
| 16 | 973 | `test/services/chat/prompt_injection_test.dart` | LIST | Prompt-injection suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 17 | 971 | `test/models/character_card_test.dart` | LIST | Character-card model suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 18 | 970 | `lib/ui/pages/repository/stoop_card_comments.dart` | SEVERAL | Stoop discussion UI plus owner kill-switch and comment list. | Split — mixed responsibilities. |
| 19 | 968 | `lib/services/chat_service.dart` | SEVERAL | ChatService shell: fields, 65 part directives, fake-pinned members, group-realism map. | Split — mixed responsibilities. |
| 20 | 963 | `lib/ui/widgets/realism_form_section.dart` | SEVERAL | Shared Realism + Porch Life authoring form used by create, edit, and group flows. | Split — mixed responsibilities. |
| 21 | 946 | `lib/services/hardware_service.dart` | SEVERAL | GPU / CPU / VRAM detection and layer suggestions. | Split — mixed responsibilities. |
| 22 | 939 | `lib/services/chat/time_service.dart` | SEVERAL | Story-clock eval, apply, skip, and failure-floor logic. | Split — mixed responsibilities. |
| 23 | 934 | `lib/services/web/web_server_host.dart` | SEVERAL | Embedded PWA server: bind, routes, auth cookie, static bundle, WebSocket hub. | Split — mixed responsibilities. |
| 24 | 927 | `lib/database/database.migrations.dart` | LIST | Byte-verbatim onUpgrade ladder (live schema 52; file header still says v44). | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 25 | 908 | `test/services/character_repository_test.dart` | LIST | Character repository suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 26 | 902 | `lib/services/kobold_service.dart` | SEVERAL | KoboldCpp HTTP client: generate, abort, extras, admin, model info. | Split — mixed responsibilities. |
| 27 | 899 | `lib/ui/pages/chat_page.dart` | SEVERAL | Desktop chat page shell: bubble keys, send, overlays, sidebar host. | Split — mixed responsibilities. |
| 28 | 894 | `test/services/chat/growth_test.dart` | LIST | Growth Rings suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 29 | 889 | `lib/services/chat/pockets.dart` | SEVERAL | Pockets / wardrobe model, op grammar, applier, and related types. | Split — mixed responsibilities. |
| 30 | 881 | `lib/ui/chat_components/sidebar/journal_memory/growth_panel.dart` | SEVERAL | Growth sidebar panel plus in-place ring editor dialog. | Split — mixed responsibilities. |
| 31 | 876 | `lib/ui/widgets/chance_time_overlay.dart` | SEVERAL | Chance Time overlay, wheel, confetti, and category chrome. | Split — mixed responsibilities. |
| 32 | 868 | `lib/services/open_router_service.dart` | SEVERAL | Remote OpenAI-shaped client: chat, tools, catalog, and provider extras. | Split — mixed responsibilities. |
| 33 | 862 | `web_ui/src/components/ChatTools.tsx` | SEVERAL | Web chat-tools sidebar: every desktop tool section mirrored in TSX. | Split — mixed responsibilities. |
| 34 | 852 | `lib/services/chat/llm_eval_engine.dart` | SEVERAL | Shared eval fire, think-strip, JSON extract, retry, and hang guards. | Split — mixed responsibilities. |
| 35 | 849 | `test/services/chat/lorebook_scanner_test.dart` | LIST | Lorebook scanner suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 36 | 834 | `lib/models/character_card.dart` | ONE | V2 / V2.5 character card model and (de)serialization. | Do not split for size — one responsibility that happens to be long. |
| 37 | 826 | `lib/services/chat/chat_service_accessors.dart` | SEVERAL | ChatService getters, today-sentence, planner resolve, and related facades. | Split — mixed responsibilities. |
| 38 | 822 | `lib/services/chat/needs_impact_evaluator.dart` | SEVERAL | Post-gen needs-impact eval, activity table, and modifier pipeline. | Split — mixed responsibilities. |
| 39 | 816 | `lib/services/chat/chat_service_session_manage.dart` | SEVERAL | Rename, fork, delete, new-chat, and session description. | Split — mixed responsibilities. |
| 40 | 815 | `lib/services/chat/chat_command_handler.dart` | SEVERAL | Slash commands plus Scene Guest mint. | Split — mixed responsibilities. |
| 41 | 810 | `test/services/image_gen_generate_test.dart` | LIST | Image-gen generate suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 42 | 803 | `lib/services/chat/realism_verification.dart` | SEVERAL | Director / verifier critique and rule apply. | Split — mixed responsibilities. |
| 43 | 802 | `lib/ui/character_creator/steps/setup_step.dart` | SEVERAL | Creator step 0: backend and model setup plus status dots. | Split — mixed responsibilities. |
| 44 | 798 | `test/ui/pages/repository/stoop_card_comments_test.dart` | LIST | Stoop comments widget suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 45 | 791 | `lib/services/chat/chat_service_reprocess.dart` | SEVERAL | Manual reprocess, revert, and regenerate orchestration. | Split — mixed responsibilities. |
| 46 | 780 | `test/services/chat/realism_evals_test.dart` | LIST | Realism eval suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 47 | 776 | `lib/services/web/facade/chat_facade.dart` | SEVERAL | Web chat send / load / history / swipe adapter. | Split — mixed responsibilities. |
| 48 | 746 | `test/services/chat/fpchat_group_fork_test.dart` | LIST | fpchat group-fork suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 49 | 744 | `lib/ui/chat_components/sidebar/story_tools/chat_places_panel.dart` | ONE | This-chat places / worlds sidebar panel. | Do not split for size — one responsibility that happens to be long. |
| 50 | 744 | `lib/services/chat/chat_service_session_load.dart` | SEVERAL | Load last session, list sessions, hydrate a session. | Split — mixed responsibilities. |
| 51 | 744 | `lib/services/chat/chat_service_objectives.dart` | SEVERAL | Objectives load, inject, tasks, and completion checks. | Split — mixed responsibilities. |
| 52 | 739 | `test/ui/pages/styled_text_controller_api_test.dart` | LIST | Styled text controller API suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 53 | 738 | `test/golden/support/fakes.dart` | LIST | Golden / widget-test fake graph. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 54 | 735 | `lib/services/update_service.dart` | SEVERAL | Update check, download, and install orchestration. | Split — mixed responsibilities. |
| 55 | 727 | `lib/ui/widgets/group_member_card.dart` | SEVERAL | Group member card: portrait, needs, affection, menus. | Split — mixed responsibilities. |
| 56 | 712 | `lib/ui/dialogs/data_bank_dialog.dart` | SEVERAL | Data Bank editor dialog. | Split — mixed responsibilities. |
| 57 | 711 | `test/services/system_role_probe_test.dart` | LIST | System-role probe suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 58 | 711 | `lib/services/world_repository.dart` | SEVERAL | World CRUD, attach, and climate helpers. | Split — mixed responsibilities. |
| 59 | 710 | `lib/services/chat/needs_simulation.dart` | ONE | Needs decay, scene apply, and vector math. | Do not split for size — one responsibility that happens to be long. |
| 60 | 704 | `lib/database/database_cleanup.dart` | SEVERAL | Orphan scan, report, and destructive cleanup. | Split — mixed responsibilities. |
| 61 | 702 | `web_ui/src/components/PorchLifeSettings.tsx` | ONE | Web Porch Life settings form. | Do not split for size — one responsibility that happens to be long. |
| 62 | 701 | `test/services/chat/chat_command_handler_test.dart` | LIST | Slash-command suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 63 | 697 | `test/services/open_router_structured_eval_test.dart` | LIST | Remote structured-eval suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 64 | 687 | `lib/ui/pages/edit_character_page.dart` | SEVERAL | Edit-character page shell plus tab host. | Split — mixed responsibilities. |
| 65 | 679 | `lib/services/memory_service.dart` | SEVERAL | RAG embed, store, retrieve. | Split — mixed responsibilities. |
| 66 | 678 | `lib/ui/pages/repository/stoop_browse_view.dart` | SEVERAL | Stoop browse / search / sort view. | Split — mixed responsibilities. |
| 67 | 675 | `test/models/lorebook_test.dart` | LIST | Lorebook model suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 68 | 675 | `lib/services/chat/chat_service_wiring_evals.dart` | SEVERAL | Builders that construct the eval pipeline leaves. | Split — mixed responsibilities. |
| 69 | 674 | `test/utils/output_sanitizer_regex_test.dart` | LIST | Output-sanitizer regex suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 70 | 670 | `lib/ui/dialogs/generate_kcpps_dialog.dart` | SEVERAL | Generate-kcpps dialog. | Split — mixed responsibilities. |
| 71 | 666 | `test/services/chat/pockets_test.dart` | LIST | Pockets / wardrobe suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 72 | 666 | `lib/ui/pages/model_manager_page.dart` | SEVERAL | Local model manager page. | Split — mixed responsibilities. |
| 73 | 664 | `lib/services/backporch/backporch_api.dart` | ONE | Stoop HTTPS client (additive-only contract). | Do not split for size — one responsibility that happens to be long. |
| 74 | 658 | `lib/services/chat/chat_service_wiring_injection.dart` | SEVERAL | Builders for prompt-injection leaves. | Split — mixed responsibilities. |
| 75 | 654 | `lib/services/chat/rag_injection.dart` | SEVERAL | RAG prompt block plus per-turn receipt helpers. | Split — mixed responsibilities. |
| 76 | 651 | `lib/database/data_migration_service.dart` | ONE | Cross-schema data migrations. | Do not split for size — one responsibility that happens to be long. |
| 77 | 649 | `lib/services/chat/chat_service_send.dart` | SEVERAL | sendMessage spine: pre-turn capture, decay, generate handoff. | Split — mixed responsibilities. |
| 78 | 640 | `lib/ui/dialogs/group_objectives_dialog.dart` | ONE | Group objectives editor dialog. | Do not split for size — one responsibility that happens to be long. |
| 79 | 638 | `test/services/chat_message_test.dart` | LIST | ChatMessage model suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 80 | 637 | `lib/ui/pages/repository/stoop_card_detail_page.dart` | SEVERAL | Stoop card detail panel plus navigation to creator. | Split — mixed responsibilities. |
| 81 | 637 | `lib/services/web/facade/character_facade.dart` | SEVERAL | Web character CRUD / import adapter. | Split — mixed responsibilities. |
| 82 | 635 | `test/models/greeting_realism_seed_test.dart` | LIST | Greeting realism-seed suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 83 | 635 | `lib/ui/image_studio/image_studio.dart` | SEVERAL | Image Studio canvas shell and subject selector. | Split — mixed responsibilities. |
| 84 | 634 | `lib/services/chat/growth_store.dart` | SEVERAL | Growth ring persistence and cursor. | Split — mixed responsibilities. |
| 85 | 632 | `test/services/chat/relationship_service_test.dart` | LIST | Relationship service suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 86 | 629 | `lib/services/user_persona_service.dart` | SEVERAL | User persona model plus store. | Split — mixed responsibilities. |
| 87 | 622 | `lib/services/chat/chat_service_pockets.dart` | SEVERAL | ChatService pockets pass, intro, and persist. | Split — mixed responsibilities. |
| 88 | 620 | `lib/ui/pages/story_home_view.dart` | ONE | Porch Stories home list. | Do not split for size — one responsibility that happens to be long. |
| 89 | 619 | `lib/ui/dialogs/background_settings_dialog.dart` | ONE | Chat background settings dialog. | Do not split for size — one responsibility that happens to be long. |
| 90 | 618 | `test/services/chat/time_service_test.dart` | LIST | Story-clock suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 91 | 618 | `test/services/chat/llm_eval_engine_test.dart` | LIST | Eval-engine suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 92 | 612 | `integration_test/app_smoke_test.dart` | LIST | 1:1 E2E smoke journey. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 93 | 606 | `lib/services/web/facade/settings_facade.dart` | SEVERAL | Web settings read/write matrix over StorageService. | Split — mixed responsibilities. |
| 94 | 597 | `lib/ui/pages/story_structure_page.dart` | ONE | Story structure editor page. | Do not split for size — one responsibility that happens to be long. |
| 95 | 595 | `web_ui/src/hooks/useLibrary.ts` | SEVERAL | Web library hook: characters, groups, folders, worlds. | Split — mixed responsibilities. |
| 96 | 590 | `lib/ui/dialogs/story_calendar_dialog.dart` | ONE | Story calendar / set-date dialog. | Do not split for size — one responsibility that happens to be long. |
| 97 | 589 | `lib/utils/emotion_labels.dart` | LIST | Emotion label maps and family tables. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 98 | 587 | `test/services/capability/reasoning_support_test.dart` | LIST | Reasoning-support suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 99 | 587 | `lib/services/backend_manager.dart` | SEVERAL | Managed KoboldCpp process lifecycle. | Split — mixed responsibilities. |
| 100 | 586 | `test/services/chat/realism_verification_test.dart` | LIST | Director / verifier suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 101 | 585 | `lib/services/chat/chat_service_cast.dart` | SEVERAL | Cast shrink / guest remove operations. | Split — mixed responsibilities. |
| 102 | 584 | `lib/models/story_project.dart` | LIST | Story project model fields. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 103 | 583 | `test/utils/vram_estimator_test.dart` | LIST | VRAM estimator suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 104 | 578 | `lib/services/chat/journal_maintenance.dart` | ONE | Journal periodic pass. | Do not split for size — one responsibility that happens to be long. |
| 105 | 577 | `lib/ui/dialogs/journal_dialog.dart` | ONE | Full journal diary dialog. | Do not split for size — one responsibility that happens to be long. |
| 106 | 574 | `lib/ui/pages/home/home_page_dialogs.dart` | SEVERAL | Home folder / delete / move dialogs. | Split — mixed responsibilities. |
| 107 | 574 | `integration_test/support/fake_backend.dart` | LIST | E2E fake backend. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 108 | 573 | `test/ui/chat_components/journal_ui_test.dart` | LIST | Journal UI suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 109 | 570 | `lib/ui/pages/home/home_page_chrome.dart` | SEVERAL | Home mode toggle and status bar. | Split — mixed responsibilities. |
| 110 | 570 | `lib/services/chat/realism_prompt_builder.dart` | ONE | Realism eval prompt text. | Do not split for size — one responsibility that happens to be long. |
| 111 | 569 | `web_ui/src/pages/SettingsPage.tsx` | ONE | Web settings page shell. | Do not split for size — one responsibility that happens to be long. |
| 112 | 569 | `lib/ui/pages/story_writer_page.dart` | ONE | Story prose writer page. | Do not split for size — one responsibility that happens to be long. |
| 113 | 566 | `lib/services/chat/realism_tools.dart` | LIST | Structured-eval tool schemas. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 114 | 563 | `test/ui/stoop_adult_lock_test.dart` | LIST | Stoop 18+ lock suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 115 | 560 | `lib/ui/widgets/group_realism_dynamics_editor.dart` | ONE | Group inter-character dynamics editor. | Do not split for size — one responsibility that happens to be long. |
| 116 | 558 | `lib/services/chat/chat_service_generation_postgen.dart` | SEVERAL | Post-gen finalize: needs, reply-facts, climax, pockets, posture. | Split — mixed responsibilities. |
| 117 | 554 | `lib/ui/pages/home_page.dart` | ONE | Home page shell. | Do not split for size — one responsibility that happens to be long. |
| 118 | 554 | `lib/services/image_prompt/image_prompt_builder.dart` | ONE | Image-prompt builder. | Do not split for size — one responsibility that happens to be long. |
| 119 | 553 | `lib/services/system_role_probe.dart` | ONE | System-role capability probe. | Do not split for size — one responsibility that happens to be long. |
| 120 | 550 | `lib/ui/pages/settings_page.gpu.dart` | ONE | Settings GPU / offload tab. | Do not split for size — one responsibility that happens to be long. |
| 121 | 548 | `test/ui/avatar_creation/avatar_creation_controller_test.dart` | LIST | Avatar creation controller suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 122 | 545 | `lib/services/chat/chat_service_generation_plan.dart` | ONE | Generation plan phase. | Do not split for size — one responsibility that happens to be long. |
| 123 | 544 | `web_ui/src/pages/stoop/StoopAccountPage.tsx` | SEVERAL | Stoop account / follow / messages page. | Split — mixed responsibilities. |
| 124 | 544 | `lib/services/chat/promise_debt_service.dart` | ONE | Promise and debt tracking. | Do not split for size — one responsibility that happens to be long. |
| 125 | 543 | `lib/ui/pages/settings_page.advanced.dart` | SEVERAL | Advanced settings: storage, web server, DB maintenance. | Split — mixed responsibilities. |
| 126 | 543 | `lib/ui/chat_components/bubbles/message_bubble.realism.dart` | ONE | Bubble realism / needs chips. | Do not split for size — one responsibility that happens to be long. |
| 127 | 542 | `lib/services/character_gen_service.dart` | ONE | AI character generator orchestration. | Do not split for size — one responsibility that happens to be long. |
| 128 | 539 | `test/services/web/auth_service_test.dart` | LIST | Web auth suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 129 | 539 | `lib/models/greeting_realism_seed.dart` | ONE | Greeting realism seed model. | Do not split for size — one responsibility that happens to be long. |
| 130 | 535 | `test/services/capability/vision_support_resolver_test.dart` | LIST | Vision-support resolver suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 131 | 535 | `lib/ui/avatar_creation/avatar_generation_panel.dart` | ONE | Avatar generation panel. | Do not split for size — one responsibility that happens to be long. |
| 132 | 532 | `lib/services/chat/expression_classifier.dart` | ONE | Chat-side expression classifier wrapper. | Do not split for size — one responsibility that happens to be long. |
| 133 | 531 | `lib/ui/dialogs/tts_settings_dialog.dart` | ONE | TTS settings dialog. | Do not split for size — one responsibility that happens to be long. |
| 134 | 531 | `lib/services/chat/chat_service_generation_stream.dart` | ONE | Generation stream phase. | Do not split for size — one responsibility that happens to be long. |
| 135 | 528 | `lib/ui/chat_components/overlays/rag_setup_dialog.dart` | ONE | RAG consent / setup dialog. | Do not split for size — one responsibility that happens to be long. |
| 136 | 528 | `lib/services/chat/chat_service_session_state.dart` | SEVERAL | Session dirty / hydrate / save guards. | Split — mixed responsibilities. |
| 137 | 528 | `lib/services/chat/chat_service_group_membership.dart` | SEVERAL | 1:1-to-group fork and member lifecycle. | Split — mixed responsibilities. |
| 138 | 527 | `test/services/story_pipeline_leaves_test.dart` | LIST | Story pipeline leaf suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 139 | 526 | `lib/services/image_gen_service.backends.dart` | SEVERAL | Image-gen disk persist plus backend generators. | Split — mixed responsibilities. |
| 140 | 526 | `lib/services/chat/growth_service.dart` | ONE | Growth Rings pass. | Do not split for size — one responsibility that happens to be long. |
| 141 | 525 | `lib/services/chat/chat_service_chat_package.dart` | SEVERAL | fpchat export / import I/O. | Split — mixed responsibilities. |
| 142 | 523 | `test/integration/character_lifecycle_test.dart` | LIST | Character lifecycle integration suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 143 | 522 | `lib/ui/widgets/styled_text_controller.dart` | SEVERAL | Styled tokenizer, presets, and controller. | Split — mixed responsibilities. |
| 144 | 522 | `lib/ui/settings/tabs/general_tab.dart` | ONE | Settings General tab. | Do not split for size — one responsibility that happens to be long. |
| 145 | 520 | `lib/ui/widgets/character_card_grid.dart` | SEVERAL | Home grid: search scope, folder actions, drag, cards. | Split — mixed responsibilities. |
| 146 | 520 | `lib/services/web/facade/world_facade.dart` | SEVERAL | Web world CRUD plus lorebook import adapter. | Split — mixed responsibilities. |
| 147 | 519 | `lib/ui/dialogs/group_settings/realism_needs_tab.dart` | ONE | Group settings Realism / Needs tab. | Do not split for size — one responsibility that happens to be long. |
| 148 | 518 | `test/services/chat/posture_opening_seed_test.dart` | LIST | Posture opening-seed suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 149 | 517 | `test/services/chat/journal_physics_test.dart` | LIST | Journal physics suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 150 | 517 | `lib/ui/pages/edit_character_page.tabs_core.dart` | ONE | Edit-character core tabs. | Do not split for size — one responsibility that happens to be long. |
| 151 | 515 | `lib/ui/widgets/vision_projector_field.dart` | ONE | Vision projector field. | Do not split for size — one responsibility that happens to be long. |
| 152 | 509 | `lib/ui/pages/home/enhance/enhance_review_body.dart` | ONE | Enhance-wizard review body. | Do not split for size — one responsibility that happens to be long. |
| 153 | 508 | `web_ui/src/stoop/stoopApi.ts` | ONE | Web Stoop client (talks to the Dart relay). | Do not split for size — one responsibility that happens to be long. |
| 154 | 508 | `web_ui/src/pages/WorldsPage.tsx` | ONE | Web worlds page. | Do not split for size — one responsibility that happens to be long. |
| 155 | 508 | `lib/ui/chat_components/bubbles/border_painters.dart` | LIST | Bubble border painters. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 156 | 505 | `lib/services/image_gen_service.dart` | ONE | Image-gen service shell. | Do not split for size — one responsibility that happens to be long. |
| 157 | 502 | `test/utils/group_realism_blobs_test.dart` | LIST | Group realism blob suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 158 | 502 | `test/services/macro_resolver_test.dart` | LIST | Macro resolver suite. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 159 | 502 | `lib/services/storage/settings/realism_settings.dart` | LIST | RealismSettings field bag. | Do not split — generated, fixture, migration ladder, or a long test/list. |
| 160 | 501 | `lib/services/chat/weather_biomes.dart` | LIST | Biome / weather lookup tables. | Do not split — generated, fixture, migration ladder, or a long test/list. |

---

## Inventory B — spaghetti

Measured on the same tip. Barrel-inflated strongly connected components are a *policy* cost (36 barrels, CLAUDE.md still says "17 exist today"). Do not explode barrels to "fix" those. The genuine leaf cycles and duplicate contracts below are the payback targets.

### B1. Genuine import cycles (7)

| Cycle | Files | What to do later |
| --- | --- | --- |
| Home-grid quartet | `lib/ui/widgets/character_card_grid.dart` ↔ `lib/ui/pages/home/cards/character_grid_card.dart` ↔ `lib/ui/pages/home/widgets/home_grid_search_bar.dart` ↔ `lib/ui/pages/home/widgets/home_grid_toolbar.dart` | Extract `SearchScope` and `FolderDialogAction` to a tiny types file. Cards and chrome import types only. |
| Waifu language | `lib/services/waifu/waifu_lang_catalog.dart` ↔ `waifu_lang_runtime.dart` ↔ `waifu_session.dart` | Extract shared language types. Catalog stays data; runtime stays apply; session stays persist. |
| Realism evals ↔ verification | `lib/services/chat/realism_evals.dart` ↔ `lib/services/chat/realism_verification.dart` | Invert one import or extract the shared typedef / recent-exchange helper. Keep `fireStructuredEval` as the one fire path. |
| Lorebook ↔ codec | `lib/models/lorebook.dart` ↔ `lib/models/lorebook_codec.dart` | Codec must not import the model if the model imports the codec. Move shared DTOs one way. |
| Character repo ↔ world repo | `lib/services/character_repository.dart` ↔ `lib/services/world_repository.dart` | Extract the shared attach / name helper. Both repos call it. |
| Stoop detail ↔ creator | `lib/ui/pages/repository/stoop_card_detail_page.dart` ↔ `lib/ui/pages/repository/stoop_creator_page.dart` | Extract the navigation / profile helper. Pages import it, not each other. |
| Worker GPU | `lib/services/worker_gpu_hosts.dart` ↔ `lib/services/worker_gpu_swap.dart` | Extract host/swap types. |

Barrel SCCs (do **not** treat as bugs): services+models ~238 files, UI ~153 files. Those exist because barrels re-export siblings. Fix unused *exports*, not the barrel idea.

### B2. Duplicate contracts (same job, more than one implementation)

| Contract | Live canon | Extra copies (unify later) |
| --- | --- | --- |
| Think-strip for **shown / spoken** text | `lib/utils/think_tags.dart` (`stripThinkTags`, `resolveMouthSpeech`, `closeOpenThink`) | `StoryJson.stripThinkTags`, `char_macro.stripThinkBlocks`, `story_clock_claims._stripThink`, `regen_critique_injection._stripThink`, `image_prompt_builder._stripThinkBlocks`, plus chargen / memory sites that roll their own regex. |
| Think-strip for **eval plumbing** (budget / salvage) | `LlmEvalEngine.stripThinkBlocks` | Callers that reimplement the same regex instead of taking the engine callback. |
| JSON extract from model text | `LlmEvalEngine` extract helpers | Story pipeline JSON ladder; chargen JSON ladder. Three ladders, one job. |
| Tool-support probe | `ToolTransportProbe` in `pass_support.dart` | `OpenRouterToolSupport` is a second probe for the same "does this backend+model do tools?" question. Keep both only if their *questions* differ; document that or merge. |
| OpenAI tools stream | `streamOpenAiChatToolsWithStyleRetry` (live) | `streamOpenAiChatTools` in `openai_tool_stream.dart` — zero callers. Delete the orphan (cruft C5), do not keep a second stream. |
| Web search round | `runCatalogRound` (live, `chat_service_generation_request.dart`) | `runWebSearchRound` — test-only leftover (cruft C19). |
| Lorebook import switch | desktop `import_lorebook_page.dart` | `world_facade.importLorebook` re-decides the same formats. One decoder. |
| Journal / growth receipt parse | desktop journal / growth UI | Web `JournalPanel.tsx` / `GrowthPanel.tsx` parse receipt pills again. Relay should send the already-parsed shape. |
| Settings write matrix | `StorageService` setters | `settings_facade.dart` re-lists the same keys. Facade must forward, not re-specify. |

### B3. Change-amplification paths (one product idea, many files)

These are not "delete" items. They are why splits and DRY matter. A later task that touches one of these must name every twin.

| Idea | Files that must move together | Notes |
| --- | --- | --- |
| Stoop field | Dart client, relay route, relay facade, TS client, TS types, desktop UI, web UI (6–18 files) | Additive-only on the wire. |
| Per-chat toggle | ChatService entry + group entry + session manage + import seed + sidebar + web ChatTools + settings default | Chaos is 4 seed paths. Objectives live AND is 2-of-4 on purpose. |
| Pre-gen eval | `chat_service_realism_dance` / `_evaluateRealismForUpcomingSpeaker`, three judges, one-shot, prompt builders, tools, facade | Scores the **user** line, never the reply. |
| Post-gen bookkeeping | `chat_service_generation_postgen.dart` (needs ∥ reply-facts, then climax → pockets → posture) | Continue scores **new text only**. 1:1 and group both persist via `_saveScalarsIntoGroupRealism`. |
| Think / mouth | `think_tags.dart`, `generation_postgen.dart`, stream phase, TTS, bubble `displayText` | Closed think-only speaks; unclosed stays off the bubble. |

### B4. Fan-in (context only)

Highest importers: `app_colors.dart` 373, `services.dart` 249, `models.dart` 191. Only `lib/main.dart` has zero importers (entry). Do not "clean" those barrels.

---

## Inventory C — cruft after PR #262 (40 items)

Numbered. This is the exact cruft count the PR body copies. Rechecked on tip `c11669bc`. The wiki page export in `lib/ui/pages/pages.dart` is **valid** (`world_from_wiki_page.dart` lives under `character_creator/`; not cruft). `assets/front_porch_ai_icon.png` is used by release workflows and `docs/index.html` (not unused). `tsc` was not installed here; unused TS *exports* are unconfirmed except the CSS classes below, which grep shows only in `styles.css`.

### Dead files (2)

| # | Item | Evidence | Later task |
| ---: | --- | --- | --- |
| C1 | `lib/services/waifu/waifu_chips.dart` | `waifuChipCaption` / `waifuChipDetail` have zero callers. File is only re-exported from `waifu.dart`. | T2 |
| C2 | `lib/ui/character_creator/widgets/styled_text_field.dart` | `StyledTextField` has zero callers. File is only re-exported from `character_creator/widgets/widgets.dart`. | T2 |

### Dead symbols in live files (16)

Do not delete the host file unless this list is the whole file. `WaifuPathMode` in `waifu_jail.dart` is live; only the unused types go.

| # | Symbol | File | Later task |
| ---: | --- | --- | --- |
| C3 | `decodeFpWorldString` | `lib/models/fp_world_package.dart` | T3 |
| C4 | `kEvalWallClockTimeout` | `lib/services/chat/eval_stream_guards.dart` (sibling `kFusedEvalBudget` **is** live) | T3 |
| C5 | `streamOpenAiChatTools` | `lib/services/openai_tool_stream.dart` (sibling `…WithStyleRetry` **is** live) | T3 |
| C6 | `remoteApiUrlIsOmlx` | `lib/services/storage/settings/remote_api_key_vault.dart` | T3 |
| C7 | `kWaifuLegacyDotDir` | `lib/services/waifu/waifu_brand.dart` | T3 |
| C8 | `waifuPromptSpeech` | `lib/services/waifu/waifu_coworker_prompt.dart` | T3 |
| C9 | `WaifuJail` + `WaifuJailHit` | `lib/services/waifu/waifu_jail.dart` (keep `WaifuPathMode`) | T3 |
| C10 | `waifuQuestionFromArgs` | `lib/services/waifu/waifu_question.dart` | T3 |
| C11 | `kWaifuTodosRel` | `lib/services/waifu/waifu_todos.dart` | T3 |
| C12 | `waifuTodoStatusIsDone` | `lib/services/waifu/waifu_todos.dart` | T3 |
| C13 | `waifuTodoWriteError` | `lib/services/waifu/waifu_todos.dart` | T3 |
| C14 | `kWaifuReadClipChars` | `lib/services/waifu/waifu_tokens.dart` | T3 |
| C15 | `waifuShouldCompact` | `lib/services/waifu/waifu_tokens.dart` | T3 |
| C16 | `worldLoreEntryToolSchema` | `lib/services/world_from_wiki/world_from_wiki_tools.dart` | T3 |
| C17 | `getModeLabel` | `lib/ui/image_studio/studio_helpers.dart` | T3 |
| C18 | `decodeWorldRefList` + `encodeWorldRefList` | `lib/utils/world_ref_resolver.dart` (`resolveWorldRefsToIds` / `uniqueWorldName` stay) | T3 |

### Orphan beside a live path (1)

| # | Item | Evidence | Later task |
| ---: | --- | --- | --- |
| C19 | `runWebSearchRound` | Live dispatch uses `runCatalogRound`. File comment admits this helper "remains for unit tests of the search client." That is a second implementation. Fold the tests onto `runCatalogRound` or the search client, then delete the orphan. Needs `approved-test-change` if existing tests are edited. | T4 |

### Stale notes (5)

| # | Item | What is wrong | Later task |
| ---: | --- | --- | --- |
| C20 | `CLAUDE.md` barrel count | Says **17 exist today**. Measured **36**. | T6 |
| C21 | `lib/database/database.migrations.dart` header | Says "schema v1 → v44". Ladder has `if (from < 52)`. | T6 |
| C22 | `CLAUDE.md` schema section | Stops at **Schema v45**. Live `schemaVersion` is **52**. | T6 |
| C23 | `dev-notes/refactoring-guide.md` | 2026-06 Riverpod-after-gods guide. Gods campaign finished; full Riverpod migration was rejected. Contradicts current law. | T6 |
| C24 | `docs/superpowers/specs/2026-09-05-waifu-coding-design.md` | Pre-ship design essay. Feature is in-tree. Leftover agent spec. | T6 |

### Standalone decoration tests (3)

These stay green if the *product call site* dies, because they reimplement the dance / extractor / golden. **Do not delete.** Rewire them to call the live helper. Needs `approved-test-change`.

| # | Item | Why it is decoration | Later task |
| ---: | --- | --- | --- |
| C25 | `test/services/chat/needs_verifier_hunger_delta_test.dart` local `extractInt` / `extractBool` | Comment says they copy `LlmEvalEngine.extractJsonInt`. If that helper changes or the verifier stops using it, this file stays green. | T5 |
| C26 | `test/services/chat/realism_parity_test.dart` hand-rolled load/save dance | Composes leaf services over a fake `_groupRealism` map. Does not call `_loadGroupRealismIntoScalars` / `_saveScalarsIntoGroupRealism`. Sibling comments in `group_speaker_resolution_test.dart` already call this out. | T5 |
| C27 | `test/services/chat/weather_segments_test.dart` "adding segments did NOT change the pinned daily walk" | Duplicates the weather-engine daily-walk golden. One golden, one owner. | T5 |

### Dead CSS classes (12)

All twelve appear only in `web_ui/src/styles.css` (and the built bundle). No `className` in `web_ui/src`.

| # | Class | Later task |
| ---: | --- | --- |
| C28 | `.cast-avatar` (and `.cast-avatar.initial`) | T7 |
| C29 | `.card-delete` | T7 |
| C30 | `.chat-places-chips` | T7 |
| C31 | `.tool-slider` | T7 |
| C32 | `.tool-slider-head` | T7 |
| C33 | `.story-meta` | T7 |
| C34 | `.story-cast-row` | T7 |
| C35 | `.story-act-row` | T7 |
| C36 | `.char-meta` | T7 |
| C37 | `.reader-scene` | T7 |
| C38 | `.reader-scene-head` | T7 |
| C39 | `.reader-act-title` | T7 |

### Unused generated Drift managers (1)

| # | Item | Evidence | Later task |
| ---: | --- | --- | --- |
| C40 | `lib/database/database.g.dart` manager tail | `$AppDatabaseManager` / `$$*TableFilterComposer` from line 16,692 to 24,343. Zero `.managers` callers in the app. `toJson` (544 hits) stays. | T1 |

---

## Do not touch

- Product behavior in this plan PR (already: this file only).
- `resolveMouthSpeech` contract (closed think-only speaks; unclosed cut-off stays tagged).
- #262 restored pins, `pre_eval_mouth_speech_test`, `wardrobe_message_zero` hide-not-erase.
- `cropFillR`, `CreatorEngine`, `WorkerBackendStorage`.
- `objectivesActive` AND gate; chaos four-path seed.
- Linux goldens; `test/baselines/god_files.json` empty object (do not add entries).
- `pubspec.yaml` version; `analysis_options.yaml` unless a dedicated lint task is approved.
- `onUpgrade` ladder **bodies** in `database.migrations.dart` (header comment only in T6).
- Migration / table LIST files as hand splits.
- ONE-responsibility files, split only if a later task proves a second responsibility grew in.
- Generated `*.g.dart` via `dart format`.
- Tree-wide `dart format .`.

---

## Sequenced PRs

Order: generated Drift first, then zero-caller cruft, then orphan-beside-live, then decoration rewires, then stale notes, then dead CSS, then spaghetti DRY, then SEVERAL splits biggest / most tangled first. Each PR is one wave. No "clean up the rest later" — every SEVERAL file has a named split below.

Every task below inherits the five global constraints. Dart tasks end on `dart format <touched files>` and a clean `flutter analyze --no-fatal-warnings --no-fatal-infos`.

### T1 — Turn off unused Drift managers and ratchet generated size

**Why:** `database.g.dart` is 24,343 lines. 7,652 of those are table managers the app never calls. Treating "generated" as unmanaged is how this file became the largest thing in the repo.

**Files:**

- `build.yaml` — add under the existing `drift_dev` builder:

```yaml
options:
  generate_manager: false
```

Keep the current `generate_for: lib/database/**.dart` include. Drift 2.34 documents `generate_manager` (default `true`).

- `lib/database/database.g.dart` — regenerate with `dart run build_runner build --delete-conflicting-outputs`. Do **not** hand-edit. Do **not** `dart format` it.
- `test/hygiene/generated_dart_size_test.dart` *(new)* — census of `lib/**/*.g.dart` line counts. `database.g.dart` must stay under a recorded ceiling (post-regen measured count + a small slack, then ratchet down). Other `*.g.dart` files get the same treatment. Excludes nothing that `god_file_ratchet_test.dart` already skips for a different reason: that ratchet **excludes** `.g.dart`; this one **is** the `.g.dart` ratchet.
- Do not change `test/hygiene/god_file_ratchet_test.dart` or `test/baselines/god_files.json`.

**New file boundaries:** none in product code. Generated tail (`$$CharactersTableFilterComposer` … `$AppDatabaseManager`) must disappear.

**Test that goes red if this is dropped:** the new generated-size test, proven red by restoring `generate_manager: true` (or a fixture count above the ceiling) before landing.

**Do not touch:** table classes, `tables:` list order, `onUpgrade` bodies, `toJson` / companions the app uses, schemaVersion 52.

**Verify after regen:** `git diff lib/database/database.g.dart` shows the manager tail gone and the used companions / mappers still present. App still opens a DB in `test/services/avatar_repository_test.dart` (`schemaVersion` 52).

### T2 — Delete the two dead files and their barrel exports

**Files:** `lib/services/waifu/waifu_chips.dart` (delete), `lib/services/waifu/waifu.dart` (drop the export), `lib/ui/character_creator/widgets/styled_text_field.dart` (delete), `lib/ui/character_creator/widgets/widgets.dart` (drop the export).

**New file boundaries:** none.

**Test that goes red if the product needed them:** none today (zero callers). Add a tiny hygiene grep test *or* rely on analyze unused-export if the barrel would warn. Prefer: after delete, `flutter analyze` on the barrels is clean, and a new `test/hygiene/dead_surface_test.dart` that fails if those two paths return.

**Do not touch:** other waifu exports; `StyledTextController` (different file, live).

Covers **C1, C2**.

### T3 — Delete the 16 dead symbols in live files

One PR, grouped so each host file stays buildable. After each deletion, grep the symbol (should be zero) and run analyze on that file.

| Host file | Remove | Keep |
| --- | --- | --- |
| `fp_world_package.dart` | `decodeFpWorldString` | `FpWorldPackage` and encode / other decoders that have callers |
| `eval_stream_guards.dart` | `kEvalWallClockTimeout` | `kFusedEvalBudget`, think-dump guards |
| `openai_tool_stream.dart` | `streamOpenAiChatTools` | `streamOpenAiChatToolsWithStyleRetry` |
| `remote_api_key_vault.dart` | `remoteApiUrlIsOmlx` | vault read/write |
| `waifu_brand.dart` | `kWaifuLegacyDotDir` | live brand constants |
| `waifu_coworker_prompt.dart` | `waifuPromptSpeech` | live prompt builders |
| `waifu_jail.dart` | `WaifuJail`, `WaifuJailHit` | `WaifuPathMode` |
| `waifu_question.dart` | `waifuQuestionFromArgs` | `WaifuQuestionRequest` if callers exist |
| `waifu_todos.dart` | `kWaifuTodosRel`, `waifuTodoStatusIsDone`, `waifuTodoWriteError` | live todo helpers with callers |
| `waifu_tokens.dart` | `kWaifuReadClipChars`, `waifuShouldCompact` | live token helpers with callers |
| `world_from_wiki_tools.dart` | `worldLoreEntryToolSchema` | live wiki tools |
| `studio_helpers.dart` | `getModeLabel` | live studio helpers |
| `world_ref_resolver.dart` | `decodeWorldRefList`, `encodeWorldRefList` | `resolveWorldRefsToIds`, `uniqueWorldName` |

**New file boundaries:** none. If a host file becomes empty except a copyright, delete the file and the barrel export in the same PR.

**Test that goes red:** new `test/hygiene/dead_surface_test.dart` (same file as T2 or an add) listing these symbol names; it greps `lib/` and fails if they return. Proven red by leaving one symbol in.

**Do not touch:** OpenCode jail (`folderJail:` in `waifu_opencode.dart`); that is the live path-scope. Do not "restore" `WaifuJail` as a second jail.

Covers **C3–C18**.

### T4 — Fold `runWebSearchRound` into the live catalog path

**Files:** `lib/services/chat/web_search_service.dart` (delete `runWebSearchRound`), `lib/services/chat/catalog_round.dart` (keep `runCatalogRound`), `test/services/chat/web_search_service_test.dart` (point at `runCatalogRound` or the search client; needs `approved-test-change`).

**New file boundaries:** none.

**Test that goes red if search dies:** existing `web_search_service_test` / `web_search_security_test` / `wiki_search_test` after they call the live function. Proven red by deleting `runCatalogRound` (not by deleting a leftover).

**Do not touch:** `kWikipediaSearchEndpoint` (test-only constant that pins the live URL — that is a pin, not decoration).

Covers **C19**.

### T5 — Rewire the three decoration tests to the product

Needs `approved-test-change`. Do not delete the files.

1. **C25** `needs_verifier_hunger_delta_test.dart` — call `LlmEvalEngine.extractJsonInt` / the real extractor the verifier uses. Keep the strict hunger_delta vs hunger assertion. Proven red by flipping the verifier back to plain `'hunger'`.
2. **C26** `realism_parity_test.dart` — drive `ChatService` load/save (`_loadGroupRealismIntoScalars` / `_saveScalarsIntoGroupRealism`) or a public test hook those methods already have. Leaf services stay. Proven red by breaking the real dance (cross-speaker write) while leaving the hand-rolled map intact.
3. **C27** `weather_segments_test.dart` — delete the duplicated daily-walk golden; leave a single owner in the weather-engine suite. Keep segment-specific tests (hour-independence, words-only). Proven red by changing the engine walk without updating the one remaining golden.

**Do not touch:** #262 call-site pins; Linux weather goldens if any.

### T6 — Fix the five stale notes

Docs / comments only. No product code.

- C20: `CLAUDE.md` barrel sentence → "36 exist today" and keep the `find` one-liner.
- C21: `database.migrations.dart` header + library doc → "schema v1 → v52". Do not edit `if (from < N)` bodies.
- C22: `CLAUDE.md` Database section — add v46–v52 as short bullets next to v45 (objectives default stays load-bearing). Do not invent column lists; copy from the live `if (from < N)` comments.
- C23: Replace `dev-notes/refactoring-guide.md` with a stub that points at `CLAUDE.md` (same shape as `AGENTS.md`), or delete it if `dev-notes/README.md` already points at CLAUDE. Do not revive a Riverpod-migration project.
- C24: Delete `docs/superpowers/specs/2026-09-05-waifu-coding-design.md` once `docs/design/` (or the in-tree waifu files) is the live spec. If something still inbound-links it, retarget that link first.

**Test that goes red:** none required (docs). A comment-vs-schema pin already exists (`test/database/objectives_enabled_migration_test.dart`, `avatar_repository_test` `schemaVersion == 52`). After C21, those stay green.

**Do not touch:** ladder SQL.

### T7 — Remove 12 dead CSS classes; then split `styles.css`

`web_ui/src/styles.css` is 2,960 lines and SEVERAL. Two commits in one PR are fine if the first is delete-only.

**Step A (C28–C39):** delete the unused rules. Rebuild `web_ui` (`npm run build` writes `assets/web_app`). Grep the twelve names in `web_ui/src` — still zero.

**Step B (split, file #3 in inventory):** cut by the existing 58 section comments into files under `web_ui/src/styles/` and one `styles.css` that `@import`s them. Proposed first cut (merge small adjacent sections so no file is a 20-line toy):

| New file | Sections |
| --- | --- |
| `styles/tokens.css` | variables, reset, typography |
| `styles/shell.css` | app shell, nav, layout |
| `styles/chat.css` | chat page, bubbles, composer, overlays |
| `styles/sidebar.css` | tools sidebar, sliders that remain live |
| `styles/library.css` | home / cards / folders |
| `styles/stoop.css` | hub / browse / detail |
| `styles/stories.css` | stories, reader |
| `styles/settings.css` | settings / porch life |
| `styles/waifu.css` | waifu coder chrome (if present) |

**Test that goes red:** visual — `npm run build` plus a grep that `styles.css` (the entry) still imports every fragment. Widget / Playwright if the repo has a web visual test; otherwise the maintainer poke script below. Do not add a decoration "file exists" test.

**Do not touch:** class names that TSX still uses; warm-porch variables.

`npm run build` is required after any `web_ui` change.

---

## T8 — Unify think-strip (spaghetti, after cruft)

**Canon (do not invent a third):**

- Shown / spoken / stored bubble text → `think_tags.dart` (`stripThinkTags`, `resolveMouthSpeech`, `closeOpenThink`).
- Eval plumbing (budget, salvage, JSON extract) → `LlmEvalEngine.stripThinkBlocks`.

**Replace these copies with a call to the matching canon:**

| Copy | File | Which canon |
| --- | --- | --- |
| `StoryJson.stripThinkTags` | `lib/services/story/story_json.dart` | `stripThinkTags` (or a one-line forwarder if the story name must stay) |
| `stripThinkBlocks` | `lib/services/chargen/char_macro.dart` | `stripThinkTags` or engine, whichever the chargen call site is doing |
| `_stripThink` | `lib/services/chat/story_clock_claims.dart` | `stripThinkTags` |
| `_stripThink` | `lib/services/chat/prompt_injection/regen_critique_injection.dart` | `stripThinkTags` |
| `_stripThinkBlocks` | `lib/services/image_prompt/image_prompt_builder.dart` | `stripThinkTags` |

Grep `replaceAll(.*think` under `lib/` after this PR — leftover copies become the next nibble, not a new contract.

**Test that goes red if mouth / eval strip is dropped:** `test/services/chat/pre_eval_mouth_speech_test.dart` (mouth); `test/services/chat/eval_orphan_think_strip_test.dart` / `llm_eval_engine_test.dart` (eval). Do not edit those pins. Add a new test only if a deleted copy had unique behavior — then that behavior belongs in the canon, with a proven-red test there.

**Do not touch:** `resolveMouthSpeech` cases; Continue salvage (`generation_stream_behavior_test`).

### T9 — One lorebook import decoder

**Files:** `lib/ui/pages/import_lorebook_page.dart`, `lib/services/web/facade/world_facade.dart`, plus the existing lorebook codec.

**New file:** `lib/models/lorebook_import.dart` (or extend `lorebook_codec.dart` if that is already the decoder). Desktop page and web facade call it. No second switch.

**Test that goes red:** `test/models/lorebook_test.dart` plus a new call-site pin that both `import_lorebook_page.dart` and `world_facade.dart` mention the shared function name (same shape as `chaos_global_toggle_test`).

**Do not touch:** Stoop additive JSON contract.

### T10 — Journal / growth receipt shape is parsed once

**Files:** desktop journal / growth panels, `journal_web_surface.dart` / growth web surface, `web_ui/src/components/JournalPanel.tsx`, `GrowthPanel.tsx`.

Relay sends `{ receipts: number[] }` already parsed. TSX must not re-parse a string. If it already receives numbers, delete the leftover string parser.

**Test that goes red:** journal / growth UI tests plus a facade test that a receipt pill is an int. Twin law: if Journal invalidates on rewrite, Growth must too.

### T11 — Settings facade forwards, does not re-list

**Files:** `lib/services/web/facade/settings_facade.dart` (606, SEVERAL). Split by domain (generation / backend / porch-life / voice) **or** shrink by deleting duplicated key tables in favor of `StorageService` getters. Prefer shrink-then-split.

**Test that goes red:** `integration_test/settings_persistence_test.dart` (stays put). Web settings write of one flag must still round-trip.

**Do not touch:** pref key strings; nightly `beta_` prefix.

### T12 — Dual tool probes: document or merge

**Files:** `lib/services/chat/pass_support.dart` (`ToolTransportProbe`), `lib/services/openrouter_tool_support.dart` (`OpenRouterToolSupport`).

If they answer different questions (catalog vs in-band probe), write that in one comment on each class and stop. If they answer the same question, merge into `ToolTransportProbe`. No third probe.

**Test that goes red:** `test/services/chat/tool_support_test.dart`, `test/services/openrouter_native_tools_test.dart`.

---

## T13+ — Split every SEVERAL file (66 targets)

Rules for every split PR:

- Mechanical extract. No behavior change.
- New Dart files under 500 lines. Parent ends under 500.
- `part of` only when the code must touch `ChatService` privates; otherwise a real library.
- Fake-pinned `ChatService` members stay on the class as one-line forwarders (golden fakes dispatch on the class member).
- One domain per PR when the file is a ChatService part (path-complete).
- After extract: barrels, `dart format` on touched Dart, analyze clean.
- God-file ratchet must stay green (no `lib/` file ≥ 1,000).

**Test that goes red** is named per file. Prefer an existing call-site pin. If none exists, add one *before* the split (new file, no `approved-test-change`).

Below, "boundaries" are the new files. Line counts are pre-split.

### Wave S1 — biggest mixed files (do these first)

#### S1.1 `chat_tools_facade.dart` (995)

| New file | Holds |
| --- | --- |
| `chat_tools_facade.dart` | ctor, snapshot, notify |
| `chat_tools_facade.memory.dart` | journal / growth / RAG / summary |
| `chat_tools_facade.realism.dart` | chaos, NSFW, clock, weather, director |
| `chat_tools_facade.objectives.dart` | objectives / tasks |
| `chat_tools_facade.pockets.dart` | pockets / wardrobe |

`part of` the facade library is fine (one class, many sections).

**Red if dropped:** web ChatTools route tests + `integration_test/sidebar_sweep_test.dart` (desktop twin). Continue / group: facade must still forward, not reimplement.

#### S1.2 `stoop_upload_page.dart` (990)

| New file | Holds |
| --- | --- |
| `stoop_upload_page.dart` | shell, step index, nav |
| `stoop_upload_pick.dart` | character / group / world pick |
| `stoop_upload_details.dart` | details + adult + comments ack |
| `stoop_upload_publish.dart` | `_publish` / `_publishGroup` / `_publishWorld` |

Wizard must keep the create-character top-bar step dots (`_currentStep`, `AnimatedSwitcher`, bottom nav).

**Red if dropped:** Stoop share / upload widget or E2E (`integration_test/stoop_test.dart`).

#### S1.3 `create_group_chat_page.dart` (988)

| New file | Holds |
| --- | --- |
| `create_group_chat_page.dart` | shell + steps |
| `create_group_roster.dart` | member pick |
| `create_group_settings.dart` | name / scenario / defaults |
| `create_group_commit.dart` | persist + open |

Same wizard chrome rule as S1.2.

**Red if dropped:** group create widget test; `integration_test/group_smoke_test.dart` still opens a group.

#### S1.4 `creator_state.dart` (987)

| New file | Holds |
| --- | --- |
| `creator_state.dart` | fields + notify |
| `creator_state_prefs.dart` | load / save / reset |
| `creator_state_steps.dart` | step machine |
| `creator_state_generate.dart` | generation kickoff |

`CreatorEngine` stays (production + goldens).

**Red if dropped:** `test/ui/character_creator/creator_modes_test.dart`, creator engine goldens.

#### S1.5 `web_ui/src/pages/ChatPage.tsx` (978)

| New file | Holds |
| --- | --- |
| `ChatPage.tsx` | route shell, auth, layout branch |
| `chat/useChatSession.ts` | load / socket / history |
| `chat/useChatSend.ts` | send / continue / regen (or keep `chatSend.ts` and move the rest out of the page) |
| `chat/ChatOverlays.tsx` | chance time, reprocess, persona, image review, edit |

Desktop twin is `chat_page.dart` (S1.8). Web/mobile separate shells are allowed; do not merge desktop and phone into one CSS path.

**Red if dropped:** web chat send / load tests if present; otherwise `integration_test/web_server_test.dart` plus a poke script.

#### S1.6 `stoop_card_comments.dart` (970)

| New file | Holds |
| --- | --- |
| `stoop_card_comments.dart` | list + composer |
| `stoop_card_discussion.dart` | discussion block + owner kill switch |

**Red if dropped:** `test/ui/pages/repository/stoop_card_comments_test.dart`, `test/services/backporch/stoop_comment_gate_test.dart`.

#### S1.7 `chat_service.dart` (968)

Shell only. Extract more fields / builders into existing wiring parts. Do not grow this file.

| Destination | Holds |
| --- | --- |
| existing `chat_service_wiring_*.dart` | remaining `late final` constructions |
| `chat_service_defaults.dart` (already) | default prompts / thresholds |
| keep on the class | fake-pinned one-line forwarders |

**Red if dropped:** god-file ratchet (file must stay < 1,000) plus any golden fake that overrides a moved member (those fakes must keep compiling).

**Do not touch:** `_groupRealism` ownership; 65 part list except adding a new part when an extract needs it.

#### S1.8 `realism_form_section.dart` (963)

| New file | Holds |
| --- | --- |
| `realism_form_section.dart` | section scaffold |
| `realism_form_engine.dart` | engine / one-shot / judges toggles |
| `realism_form_needs.dart` | needs / decay |
| `realism_form_porch.dart` | porch-life extras (chaos default, weather, clock) |

Used by create, edit, and group. One form, three hosts — do not fork.

**Red if dropped:** settings / character-form tests that flip a Porch Life switch; chaos global toggle test still sees the default control.

#### S1.9 `hardware_service.dart` (946)

| New file | Holds |
| --- | --- |
| `hardware_service.dart` | public API |
| `hardware_nvidia.dart` | nvidia-smi parse |
| `hardware_apple.dart` | Apple GPU |
| `hardware_estimate.dart` | VRAM / layer suggest |

**Red if dropped:** `test/utils/vram_estimator_test.dart` plus hardware service tests if present.

#### S1.10 `time_service.dart` (939)

| New file | Holds |
| --- | --- |
| `time_service.dart` | public API, gates |
| `time_service_eval.dart` | LLM minutes decide |
| `time_service_apply.dart` | clamp, failure floor, new_day, OOC skip |

Clock is decoupled from the engine (`standaloneClockEnabled`). Continue does not tick.

**Red if dropped:** `test/services/chat/time_service_test.dart`, `test/services/chat/standalone_clock_test.dart`, `integration_test/story_time_test.dart`.

#### S1.11 `web_server_host.dart` (934)

| New file | Holds |
| --- | --- |
| `web_server_host.dart` | bind / lifecycle |
| `web_server_host.streams.dart` | overlay / live-sync relays |
| `web_server_host.wiring.dart` | facade assembly, bind, remote setup |

The inventory guessed `web_server_static` / `web_server_auth`. PWA bundle and cookie/login already live under `lib/services/web/routes/`. This file mixed stream relays with facade wiring. `WebServerHost.describeStartFailure` stays on the class. Extensions call `notify()`.

**Red if dropped:** `integration_test/web_server_test.dart`.

#### S1.12 `kobold_service.dart` (902)

| New file | Holds |
| --- | --- |
| `kobold_service.dart` | generate / abort (`LLMService` members stay on the class) |
| `kobold_service_admin.dart` | extras / readiness / swap / model info |
| `kobold_service_process.dart` | start / stop / console ingest |

A two-file split left admin over 500. Process start/stop is the third file. `startKobold` / `stopKobold` stay as class forwarders so `import … show KoboldService` still resolves them.

**Red if dropped:** Kobold client tests; `test/services/kobold_admin_hang_ready_test.dart`.

#### S1.13 `chat_page.dart` (899)

| New file | Holds |
| --- | --- |
| `chat_page.dart` | route, `_bubbleKeys`, send, thin `build` |
| `chat_page_overlays.dart` | chat surface + loading / call / realism / objective / ONNX |
| `chat_page_sidebar_host.dart` | app bar (includes the sidebar toggle) |

Sidebar body already lived in `chat_page.sidebar.dart`. Owner-scoped `GlobalKey`s stay on the State (`_bubbleKeys`). Never `GlobalObjectKey(msg)`. Extensions call `rebuildState`.

**Red if dropped:** `integration_test/chat_switch_smoke_test.dart`, `message_actions_test.dart`, `theme_interaction_test.dart`.

#### S1.14 `pockets.dart` (889)

| New file | Holds |
| --- | --- |
| `pockets.dart` | `Pockets`, apply |
| `pocket_item.dart` | `PocketItem`, `SetAsideItem` |
| `pocket_ops.dart` | `PocketOpKind`, `PocketOpReport`, `PocketEvent` |

Pure library. ChatService pockets pass stays in `chat_service_pockets.dart` (S2).

**Red if dropped:** `test/services/chat/pockets_test.dart`, `wardrobe_message_zero_test.dart`.

#### S1.15 `growth_panel.dart` (881)

| New file | Holds |
| --- | --- |
| `growth_panel.dart` | list / past / check-now |
| `growth_ring_editor.dart` | `_RingEditorDialog` |

Journal twin: `journal_panel.dart` / `journal_dialog.dart`. If you extract editor, share with journal only when the UX is the same; do not force it.

**Red if dropped:** growth UI tests; `integration_test/growth_rings_test.dart`.

#### S1.16 `chance_time_overlay.dart` (876)

| New file | Holds |
| --- | --- |
| `chance_time_overlay.dart` | overlay shell |
| `chance_time_wheel.dart` | wheel + pointer painters |
| `chance_time_confetti.dart` | confetti |

**Red if dropped:** Chance Time widget / overlay tests; chaos still fires with engine off.

#### S1.17 `open_router_service.dart` (868)

| New file | Holds |
| --- | --- |
| `open_router_service.dart` | chat / generate |
| `open_router_service.tools.dart` | tools + style retry |
| `open_router_service.catalog.dart` | model catalog |

**Red if dropped:** `test/services/open_router_structured_eval_test.dart`, `openrouter_native_tools_test.dart`.

#### S1.18 `web_ui/src/components/ChatTools.tsx` (862)

Mirror S1.1 sections: `ChatTools.tsx` shell + `ChatToolsMemory.tsx` + `ChatToolsRealism.tsx` + `ChatToolsObjectives.tsx`. Same capabilities as desktop.

**Red if dropped:** web tools tests; sidebar sweep twin.

#### S1.19 `llm_eval_engine.dart` (852)

| New file | Holds |
| --- | --- |
| `llm_eval_engine.dart` | fire / retry / cancel |
| `llm_eval_extract.dart` | JSON extract + think-strip (the eval canon) |

**Red if dropped:** `test/services/chat/llm_eval_engine_test.dart`, fused-eval / tool-skip tests.

### Wave S2 — ChatService parts over 500 (SEVERAL only)

Each row is one PR unless two parts are the same user action (send + postgen stay aware of each other).

| File | Lines | New boundaries | Red if dropped |
| --- | --- | --- | --- |
| `chat_service_accessors.dart` | 826 | accessors / today-sentence / planner-resolve | `objectivesActive` AND pin; today-line tests |
| `needs_impact_evaluator.dart` | 822 | eval fire / activity table / `_boundDeltas` (one bound helper, no third) | `needs_impact_evaluator_test.dart`, `needs_depletion_cap_test.dart` |
| `chat_service_session_manage.dart` | 816 | rename-fork-delete / new-chat seed (chaos seed stays here) | chaos 4-path pin; session tests |
| `chat_command_handler.dart` | 815 | slash parse / guest mint | `chat_command_handler_test.dart` |
| `realism_verification.dart` | 803 | rules / critique apply (cycle with realism_evals: T8/T12 first if needed) | `realism_verification_test.dart` |
| `setup_step.dart` | 802 | form / backend-status-dot | creator setup tests |
| `chat_service_reprocess.dart` | 791 | reprocess / revert / regen | `needs_reprocess` / swipe tests; Continue is **not** this file |
| `chat_facade.dart` | 776 | send-load / swipe-history | web chat tests; Continue vs regen both forwarded |
| `chat_service_session_load.dart` | 744 | list / hydrate | `load_session_objectives_test.dart` |
| `chat_service_objectives.dart` | 744 | inject / tasks / completion | `one_shot_objectives_gate_test.dart`; live AND stays |
| `update_service.dart` | 735 | check / download / install | update service tests |
| `group_member_card.dart` | 727 | card / menus (needs grid stays shared) | group member widget tests |
| `data_bank_dialog.dart` | 712 | list / editor | data bank tests |
| `world_repository.dart` | 711 | CRUD / attach (after repo cycle extract) | world / climate tests |
| `database_cleanup.dart` | 704 | scan / apply (identity via `stableGroupIdFrom`, never `characters.id` for objectives/embeddings) | cleanup tests |
| `edit_character_page.dart` | 687 | shell / tab host | edit character tests |
| `memory_service.dart` | 679 | embed / retrieve | RAG tests; `group_rag_identity_test.dart` |
| `stoop_browse_view.dart` | 678 | search / grid | stoop browse tests |
| `chat_service_wiring_evals.dart` | 675 | eval builders only (no injection) | wiring still constructs one engine |
| `generate_kcpps_dialog.dart` | 670 | form / generate | kcpps tests |
| `model_manager_page.dart` | 666 | list / download | `integration_test/model_downloader_test.dart` |
| `chat_service_wiring_injection.dart` | 658 | injection builders only | `prompt_injection_test.dart` |
| `rag_injection.dart` | 654 | block builder / receipt | `rag_injection_test.dart` |
| `chat_service_send.dart` | 649 | pre-turn capture / decay / generate handoff | send path; `preTurnVector` before `tickDecay` |
| `stoop_card_detail_page.dart` | 637 | panel / nav (after cycle extract) | stoop detail tests |
| `character_facade.dart` | 637 | read / import | web character tests |
| `image_studio.dart` | 635 | canvas / subject | image studio tests |
| `growth_store.dart` | 634 | persist / cursor (Journal twin is `journal_store.dart`) | `growth_test.dart` |
| `user_persona_service.dart` | 629 | model / store | persona tests; `integration_test/persona_folder_test.dart` |
| `chat_service_pockets.dart` | 622 | pass / intro / persist; Continue `asContinuation: true` keeps `pockets_before` | `pockets_rewind_test.dart`, `wardrobe_message_zero_test.dart` |
| `settings_facade.dart` | 606 | split after T11 shrink | settings persistence E2E |
| `useLibrary.ts` | 595 | characters / folders / worlds hooks | web library tests |
| `backend_manager.dart` | 587 | start / stop / restart | backend manager tests |
| `chat_service_cast.dart` | 585 | shrink / remove guest | cast tests |
| `home_page_dialogs.dart` | 574 | folder / delete / move | `integration_test/persona_folder_test.dart` |
| `home_page_chrome.dart` | 570 | mode toggle / status | home chrome tests |
| `chat_service_generation_postgen.dart` | 558 | needs ∥ reply-facts; climax → pockets → posture; Continue new-text only | `continue_postgen_test.dart`, `posture_after_reply_test.dart`, `reply_facts_fusion_test.dart` |
| `StoopAccountPage.tsx` | 544 | account / follow / inbox | stoop account tests |
| `settings_page.advanced.dart` | 543 | storage / web / cleanup | settings advanced tests |
| `chat_service_session_state.dart` | 528 | dirty / hydrate / save skip | session save-skip tests |
| `chat_service_group_membership.dart` | 528 | 1:1 fork / members | group membership tests |
| `image_gen_service.backends.dart` | 526 | disk / generators | `image_gen_generate_test.dart` |
| `chat_service_chat_package.dart` | 525 | fpchat I/O | `fpchat_group_fork_test.dart` |
| `styled_text_controller.dart` | 522 | tokenizer / presets / controller | `styled_text_controller_api_test.dart` |
| `character_card_grid.dart` | 520 | grid / drag (after SearchScope extract) | home grid tests |
| `world_facade.dart` | 520 | CRUD / import (after T9) | world web tests |

### Wave S3 — remaining SEVERAL UI / services already listed in S1–S2

If a SEVERAL file is not in S1 or S2, it is this row. At inventory time every SEVERAL path is in S1, S2, or T7 (`styles.css`). Re-measure before starting a wave; if a new file crossed 500, it joins the next split PR (do not leave it).

---

## Split / keep summary

| Verdict | Count | Action |
| --- | --- | --- |
| SEVERAL | 66 | Split (S1–S3 + T7 for CSS). |
| ONE | 40 | Keep. Revisit only if a second responsibility appears. |
| LIST | 54 | Keep as lists. Exception: `database.g.dart` codegen in T1. |

ONE files over 500 that people will want to "just split": `character_card.dart`, `needs_simulation.dart`, `journal_maintenance.dart`, `backporch_api.dart`, `PorchLifeSettings.tsx`. Do not. They are one job.

---

## Suggested PR order (payback sequence)

| PR | Tasks | Leaves app | Notes |
| ---: | --- | --- | --- |
| 0 | This plan | yes | docs only |
| 1 | T1 Drift managers + generated ratchet | yes | needs `build_runner`; do not format `.g.dart` |
| 2 | T2 dead files | yes | |
| 3 | T3 dead symbols | yes | |
| 4 | T4 `runWebSearchRound` | yes | may need `approved-test-change` |
| 5 | T5 decoration rewires | yes | needs `approved-test-change` |
| 6 | T6 stale notes | yes | docs |
| 7 | T7 CSS + `styles.css` split | yes | `npm run build` |
| 8 | T8 think-strip DRY | yes | path-complete for Continue / TTS / bubble |
| 9 | T9–T12 leftover spaghetti | yes | one PR per row if they fight |
| 10+ | S1.1 … S1.19 then S2 | yes | one mixed file (or one ChatService part) per PR |

No leftover SEVERAL file. Remeasured after the residual wave (tip after pass_support fire). Target met: **0 SEVERAL files over 500**. ONE and LIST may still be over 500. `chat_service.dart` (510) is the shell — keep, because a further cut fights FakeChatService class forwarders.

### Remaining production files over 500 (remeasure)

Keep verdicts only. Tests and generated files omitted.

| Lines | Path | Verdict |
| ---: | --- | --- |
| 927 | `lib/database/database.migrations.dart` | LIST — keep (onUpgrade ladder) |
| 834 | `lib/models/character_card.dart` | ONE — keep |
| 744 | `lib/ui/chat_components/sidebar/story_tools/chat_places_panel.dart` | ONE — keep |
| 710 | `lib/services/chat/needs_simulation.dart` | ONE — keep |
| 702 | `web_ui/src/components/PorchLifeSettings.tsx` | ONE — keep |
| 664 | `lib/services/backporch/backporch_api.dart` | ONE — keep |
| 651 | `lib/database/data_migration_service.dart` | ONE — keep |
| 640 | `lib/ui/dialogs/group_objectives_dialog.dart` | ONE — keep |
| 620 | `lib/ui/pages/story_home_view.dart` | ONE — keep |
| 619 | `lib/ui/dialogs/background_settings_dialog.dart` | ONE — keep |
| 597 | `lib/ui/pages/story_structure_page.dart` | ONE — keep |
| 590 | `lib/ui/dialogs/story_calendar_dialog.dart` | ONE — keep |
| 589 | `lib/utils/emotion_labels.dart` | LIST — keep |
| 584 | `lib/models/story_project.dart` | LIST — keep |
| 578 | `lib/services/chat/journal_maintenance.dart` | ONE — keep |
| 570 | `lib/services/chat/realism_prompt_builder.dart` | ONE — keep |
| 569 | `web_ui/src/pages/SettingsPage.tsx` | ONE — keep |
| 569 | `lib/ui/pages/story_writer_page.dart` | ONE — keep |
| 567 | `lib/ui/dialogs/journal_dialog.dart` | ONE — keep |
| 566 | `lib/services/chat/realism_tools.dart` | LIST — keep |
| 560 | `lib/ui/widgets/group_realism_dynamics_editor.dart` | ONE — keep |
| 556 | `lib/ui/pages/home_page.dart` | ONE — keep (shell; dialogs/chrome already extracted) |
| 553 | `lib/services/system_role_probe.dart` | ONE — keep |
| 550 | `lib/ui/pages/settings_page.gpu.dart` | ONE — keep |
| 545 | `lib/services/chat/chat_service_generation_plan.dart` | ONE — keep |
| 544 | `lib/services/chat/promise_debt_service.dart` | ONE — keep |
| 543 | `lib/ui/chat_components/bubbles/message_bubble.realism.dart` | ONE — keep |
| 539 | `lib/services/character_gen_service.dart` | ONE — keep |
| 539 | `lib/models/greeting_realism_seed.dart` | ONE — keep |
| 535 | `lib/ui/avatar_creation/avatar_generation_panel.dart` | ONE — keep |
| 532 | `lib/services/chat/expression_classifier.dart` | ONE — keep |
| 531 | `lib/ui/dialogs/tts_settings_dialog.dart` | ONE — keep |
| 531 | `lib/services/chat/chat_service_generation_stream.dart` | ONE — keep |
| 528 | `lib/ui/chat_components/overlays/rag_setup_dialog.dart` | ONE — keep |
| 528 | `lib/services/image_prompt/image_prompt_builder.dart` | ONE — keep |
| 526 | `lib/services/chat/growth_service.dart` | ONE — keep |
| 522 | `lib/ui/settings/tabs/general_tab.dart` | ONE — keep |
| 519 | `lib/ui/dialogs/group_settings/realism_needs_tab.dart` | ONE — keep |
| 517 | `lib/ui/pages/edit_character_page.tabs_core.dart` | ONE — keep |
| 515 | `lib/ui/widgets/vision_projector_field.dart` | ONE — keep |
| 510 | `lib/services/chat_service.dart` | KEEP — part list + Fake-pinned class forwarders; further cut fights fakes |
| 509 | `lib/ui/pages/home/enhance/enhance_review_body.dart` | ONE — keep |
| 508 | `web_ui/src/stoop/stoopApi.ts` | ONE — keep |
| 508 | `web_ui/src/pages/WorldsPage.tsx` | ONE — keep |
| 508 | `lib/ui/chat_components/bubbles/border_painters.dart` | LIST — keep |
| 508 | `lib/services/image_gen_service.dart` | ONE — keep (image-gen shell) |
| 502 | `lib/services/storage/settings/realism_settings.dart` | LIST — keep |
| 501 | `lib/services/chat/weather_biomes.dart` | LIST — keep |

---

## Path-complete (this PR)

N/A — documentation only. Later chat / realism / memory tasks in this plan must fill the matrix in `docs/design/path-complete-chat-work.md` (Continue ≠ regen; 1:1 ≠ group storage; Journal ↔ Growth; desktop ↔ web).

---

## Poke script (maintainer, after later PRs — not this one)

This plan PR has no runtime change. When T1+ lands:

1. Cold start, open an existing 1:1 chat, send one line, Continue once, swipe once. Bubble text and think chip still match the #262 mouth contract.
2. Open a group, send one line, confirm per-member needs / bond still update (sidebar + chips).
3. Web: open Chat tools, flip one Porch Life switch, confirm desktop and web agree after reload.

This sandbox cannot launch the desktop app or a browser against the PWA. It did not self-certify UI.

---

## Hygiene for this PR

- New private methods: none.
- Methods deleted: none.
- Product code: none.
- Formatter / analyzer: N/A (markdown only).
