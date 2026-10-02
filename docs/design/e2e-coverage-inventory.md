# E2E coverage inventory

**Why:** The maintainer cannot read Dart. Unit tests prove helpers; E2E proves
the live app still does the right thing after a full boot. This is the living
map of what `integration_test/` covers and what is still open.

**Excluded forever (cannot run autonomously):** real model downloads, real TTS
playback, real STT capture, Apple notarization, third-party OAuth browser flows,
live GPU/VRAM probes, production Stoop backend (use `fake_stoop`).

**Law:** Prefer broad journey tests. Every new High from an audit should land
an E2E (or an explicit "unit-only because …" row here). CI runs **one process
per file** — never `flutter test integration_test/`.

Update this file when you add or retire a suite.

## Legend

| Mark | Meaning |
|------|---------|
| ✅ | Covered by a named suite |
| 🔶 | Partial / weak (needs strengthening) |
| ❌ | Not covered — **priority backlog** |
| ⛔ | Explicitly out of scope |

## Suites today (`integration_test/*_test.dart`)

| Suite | What it pins |
|-------|----------------|
| `app_smoke_test` | 1:1 journey: realism, needs, chaos, objectives, journal, worlds+lore inject, backend failure resilience |
| `group_smoke_test` | Per-speaker isolation + bond/needs persistence across reload |
| `group_realism_wiring_test` | Full `_groupRealism` field inventory + prompt re-inject after reload |
| `realism_off_test` | Engine disabled path |
| `chat_switch_smoke_test` | Stacked routes + rapid A/B switch (GlobalKey class) |
| `theme_interaction_test` | Theme presets leave bubble controls hit-testable |
| `settings_persistence_test` | Settings survive reopen + reload |
| `message_actions_test` | Edit / regenerate / delete-with-needs-refund via real bubble controls |
| `swipe_fork_cancel_test` | Swipe chevrons, cancel-mid-regen put-back, fork branch |
| `web_server_test` | PWA shell, anon 401, setup→cookie→state over real HTTP |
| `web_ui/browser_test` | **Web UI in real browsers** (Playwright, WebKit phone + Chromium desktop) against the booted app: `web_ui/e2e/sweep.spec.ts` taps every safe control on every screen (fails on covered / tap-through controls, dialogs a finger can't close, phone sideways scroll, broken pictures, console errors, failing `/api`); `web_ui/e2e/journeys.spec.ts` signs in, chats, edits (#330), regenerates + swipes, continues, deletes, switches chats, persists a setting. Own CI job `web-e2e` (not in the e2e-smoke matrix — lives in a subdirectory). `FPAI_E2E_HOLD=1` keeps the sandboxed app serving for `npm run e2e` iteration. |
| `story_time_test` | Story clock advances + survives reload |
| `backup_restore_test` | Create → restore → services rebound |
| `persona_folder_test` | Persona form + session; folder create/move/open |
| `persona_default_test` | Default persona behaviour |
| `lorebook_chat_test` | This Chat lore entry → triggers → injection |
| `lorebook_import_test` | Import path |
| `worlds_management_test` | New World + Places attach |
| `climate_editor_test` | Climate editor |
| `journal_review_test` | Review-first park → banner → apply |
| `growth_rings_test` | Growth switch → pass → ring + receipt jump |
| `sidebar_sweep_test` | Accordion open + one control per section |
| `climax_refractory_test` | Climax lands + survives regen restamp |
| `needs_reprocess_test` | Manual needs reprocess wiring |
| `spell_check_test` | Spell-check language plumbing |
| `stoop_test` | Sign-in → AUP → browse → download → share (fake backporch) |
| `story_pipeline_test` | Porch Stories wizard stages |
| `story_autowrite_test` | Story autowrite |
| `model_downloader_test` | Fake-HF search/download + VRAM dialog (**fake only**) |
| `regen_feelings_cadence_test` | Group inter-char feelings do not stack across regen; cadence re-fires correctly under re-decay |
| `continue_path_test` | Continue keeps pre-continue body + new tokens; no post-gen double apply |

## Path-complete matrix (chat / realism / memory)

| Event / path | Coverage |
|--------------|----------|
| Send 1:1 | ✅ app_smoke |
| Send group per-speaker | ✅ group_smoke, group_realism_wiring |
| Continue finalize full body | ✅ continue_path_test |
| Continue + sanitizer | ❌ |
| Continue + think-strip partial | 🔶 unit only (`continue_finalize_test`) |
| Regen 1:1 | ✅ message_actions, climax_refractory |
| Regen group feelings restore | ✅ regen_feelings_cadence_test |
| Regen cadence under re-decay | ✅ regen_feelings_cadence_test |
| Swipe navigation / metadata | ✅ swipe_fork_cancel |
| Cancel mid-regen | ✅ swipe_fork_cancel |
| Fork | ✅ swipe_fork_cancel |
| Delete bot/user tail + needs refund | ✅ message_actions |
| Edit history rewrite integrity | 🔶 message_actions edit; Journal/Growth rewrite 🔶 |
| Realism off | ✅ realism_off |
| Trust-repair branch | ❌ |
| One-shot / multi-call | ❌ E2E (unit has mode tests) |
| Posture post-gen | ❌ |
| Pockets 1:1 stamp/restore | ❌ |
| Pockets group speaker restore | ❌ |
| Journal auto pass + cards | 🔶 app_smoke; review-first ✅ journal_review |
| Growth pass + rings | ✅ growth_rings |
| Journal rewrite → Growth twin | ❌ single E2E spanning both |
| RAG receipts / operational | ❌ |
| Output sanitizer global | ❌ |
| Session delete cascade | ❌ |
| Soft-delete cleanup | ❌ |
| Stoop worlds types | 🔶 stoop_test may not assert world type |
| Web Journal plant/review | ❌ (desktop journal_review only) |
| Web settings 18+ / sanitizer | ❌ |
| Passage of time / standalone clock | ✅ story_time (partial) |
| Weather / dreams | ❌ |
| Scene guest detection / accept | ❌ |
| Objectives generate tasks | 🔶 app_smoke light |
| Director / observer group | ❌ |
| Impersonate | ❌ |
| Photo turn / vision | ❌ |
| Image gen / studio | ❌ |
| Chat switch GlobalKey | ✅ chat_switch_smoke |
| Backup restore | ✅ backup_restore |
| Web server auth | ✅ web_server |
| Tunnel / 2FA step-up | ❌ (security; may stay API-level unit) |

## Priority backlog (ship next)

1. **Pockets 1:1 + group speaker restore** (audit P1 class; user-visible corruption)
2. **Continue + Output Sanitizer** (audit P0 sibling)
3. **Journal + Growth rewrite twin** one journey (delete/regen purges both)
4. **RAG receipt honesty** with embedding unavailable
5. **Pockets transfer + erase → diary** (recent features)
6. **Web parity journeys** for Journal plant/review and Porch Life 18+ — the host exists now (`web_ui/browser_test` + `web_ui/e2e/journeys.spec.ts`); add them there.
7. **Scene guest** offer → accept
8. **Director mode** group turn

## How to add a suite

1. Copy boot/sandbox header from `app_smoke_test.dart` or `climax_refractory_test.dart`.
2. Use `ChatDriver` + `FakeBackendServer` only.
3. One file = one `flutter test integration_test/that_file.dart -d macos` invocation.
4. Prove red then green for the guard (project testing law).
5. Update this inventory in the same PR.

## Run locally

```bash
# Single suite (required shape)
flutter test integration_test/regen_feelings_cadence_test.dart -d macos

# Never: flutter test integration_test/   # second file dies at loading
```
