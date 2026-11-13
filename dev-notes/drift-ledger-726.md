# Dart ⇄ PWA drift ledger (PR 726 audit, started 2026-11-11)

**Status: TABLED 2026-11-12.** Both UI inventories are complete; no further
sweep needed. Closure happens in **PR 7 of `docs/design/one-chat-ux.md`**
(the Settings page rebuild — bumped from PR 8 on 2026-11-13 when the
dropped group-only-settings PR was retired; scope split in
`docs/design/settings-rebuild-scope.md`), settings page (ledger #5) first,
then the ranked list below.

Maintainer-confirmed items get a ✅ in *Found by*; code evidence is verified in
this worktree's `web_ui/src` and `lib/`. Full inventories from the two audit
passes land as "suspects" until verified.

| # | Drift | Evidence | Found by | Status |
|---|-------|----------|----------|--------|
| 1 | Chat **Model Settings** sheet: desktop dialog embeds the full helper/worker section (helper host, Realism-evals GGUF picker, `.kcpps` preset, helper URL/key/model); the PWA chat sheet (`ChatModelSwitcher`) has provider+chat model only. Worker card exists on the PWA Settings page but is never reachable from chat. | `lib/ui/dialogs/model_settings_dialog.dart:288` (embeds `WorkerBackendSection`) vs `web_ui/src/pages/chat/ChatModelSwitcher.tsx` (no worker/helper code) ; web Settings mount: `pages/SettingsPage.tsx:627` | maintainer + code | **fixed in c5409d01b** — Realism evals lane mounts in `ChatModelSwitcher` (`ChatWorkerLane.tsx`); provider bars ride `ProviderChipBar` from `BACKEND_OPTIONS`; helper writes live-save through `POST /api/settings` with the credential step-up; a SuperGrok sign-in counts as a saved xAI key in the snapshot |
| 2 | **Web sidebar layout model differs from desktop** (maintainer: "buttons were there, but the layout defaulted different… the cast is not dragable in the dart app"). ROOT CAUSE: the PWA puts `cast` **inside** the single reorderable section list (`WIDE_DEFAULTS[0] = 'cast'`), so the cast card gets a drag grip and participates in ordering. Desktop renders the participant roster as a **fixed header above** the `ReorderableListView`, whose reorderable ids start at `director` — the cast strip is never draggable there. Consequences: different default layout, wrong interaction model for cast, and stored order keys diverge between surfaces. Secondary chrome diffs vs desktop: no collapse chevron on Director (desktop expands/collapses), step button lacks the exit-arrow icon, 🎬 emoji title vs themed Material icon, status pill grey vs green. | `web_ui/src/components/ChatSidebar.tsx:77-89` vs `lib/ui/pages/chat_page.sidebar.dart:204-260` (roster outside list) + `lib/ui/chat_components/sidebar/sidebar_body.dart:202-214` (ids start `director`) | maintainer + code | **fixed in 6a0fc24b5 (pushed)** — `cast` removed from `WIDE_DEFAULTS`; `ChatSidebar.tsx` renders `{castBar && <div className="insight-section sidebar-cast-fixed" data-id="cast">}` fixed below the layout pills, outside the reorderable body (mirrors desktop `chat_page.sidebar.dart` roster-above-list). Grip never renders for cast; stale `'cast'` keys in `ORDER_KEY` drop on the next commit (resolveOrder keeps only visible ids). Verified live at 1440px: cast pills render below Main Settings pills with no grip, Director is the first reorderable card |
| 3 | PWA Main Settings header shows a single **initials placeholder** tile where desktop shows the **cast strip with live expression portraits** | `web_ui/src/components/ChatSidebar.tsx` (expression-avatar), `CastBar.tsx:59-78` (faces ringed when focused, Away/Back, GUEST/Promote) | maintainer + code | **fixed in 3bfa3b17** — pinned by `ChatSidebar.groupState.test.tsx` |
| 4 | Home grid **folder tile**: desktop renders a portrait tile (`childAspectRatio: 0.7`) with a **2×2 avatar montage** (up to 4 member previews) + "N characters"; PWA renders a short **landscape row with a 📁 glyph and no member avatars** | `lib/ui/pages/home/cards/folder_grid_card.dart:32,152` (`_folderPreviewImages(..., 4)`, Stack montage) vs `web_ui/src/components/library/LibraryCards.tsx:97` + `web_ui/src/styles/library-cards.css:51` (`flex-direction: row`, `.folder-glyph` text only) | maintainer + code | open |
| 5 | **Settings structure (corrected after full inventory)**: desktop = 7 tabs; PWA folds Appearance into "general". Web DOES carry: dark mode + per-device theme, ambient scene/effects, pause-while-generating, scene sound + volume, mood-on-character, reading size, bubble opacity, chat colours, spell-check language. STILL MISSING: the app **theme gallery** (`ThemeCardGrid`), **accent colour** picker, **UI font**, **corners** style, and the "Reset accent, font and corners" action. | `lib/ui/settings/tabs/appearance_tab/theme_card_grid.dart`, `accent_picker_row.dart`, `appearance_tab.dart` vs `web_ui/src/components/AppearanceSettings.tsx` (grep Accent/ThemeCard → 0) | maintainer + inventories | open |
| 6 | Home toolbar has **three modes on desktop** (`enum HomeMode { chats, stories, waifu }`); PWA `HomeModeToggle` is two-mode (`'chats' \| 'stories'`). No Waifu Coder on web **at all**: no facade in `lib/services/web/` (grep waifu → 0) and no UI in `web_ui/src` | `lib/ui/pages/home/widgets/home_mode_toggle.dart:26` + `lib/ui/waifu/` (~5,900 lines, 20+ widgets) vs `web_ui/src/components/HomeModeToggle.tsx:10` | handoff + code | **ruled desktop-only, permanent** (maintainer ruling 2026-11-12; not queued) |
| 7 | Per-character Chaos (queued pre-handoff; scope not yet analyzed) | — | handoff | queued |
| 8 | Group-only settings in one place (queued pre-handoff) | — | handoff | queued |
| 9 | Dead-code sweep (queued pre-handoff) | — | handoff | queued |

## Closure order

Fix order = maintainer's call; each fix ships desktop + web in one change per
One UI rule.

| 10 | **Voice call absent from web entirely**: desktop 1:1 has `Start voice call`, `CallOverlay` (mute/send/end, Listening→Speaking status), and its settings (Voice Call Model dropdown, Voice Buffer, Call System Prompt, Auto-send); PWA composer has mic-STT and per-message Speak only | grep of `web_ui/src/components`+`pages` for voicecall/CallOverlay → 0; `lib/ui/chat_components/widgets/call_overlay/` | inventory diff + code | open |
| 11 | **Stoop upload wizard is a web stub**: desktop has the 4-step wizard (Pick/Details/Content/Review); PWA Share tab renders a "coming soon" placeholder (wide-only, phone redirects) | `web_ui/src/pages/stoop/StoopSection.tsx:102-113` vs `lib/ui/pages/repository/stoop_upload_page.dart:78` | inventory diff + code | open |
| 12 | **AI Character Creator drops the Realism step on web**: desktop `Setup → Mode → Configure → Generate → Profile → Greetings → Realism → Review`; PWA has Mode→Details→Output→Generate→Profile→Greetings — no Realism (needs/relationships/starting emotion/optional features) at generation time | grep Realism/Porch Life in `web_ui/src/pages/CreateAiCharacterPage.tsx` → 0; `lib/ui/character_creator/steps/realism_step.dart` | inventory diff + code | open |
| 13 | **Voice & Media settings thin on web beyond design**: beyond the documented ⚙️ engine-setup split, missing are Expression controls (classification LLM/ONNX/Manual, Display mode, Re-roll, Emoji Burst + size, Fallback), Whisper model download, Microphone device list, Auto-send transcription, Photo-understanding card | `lib/ui/settings/tabs/voice_media_tab/expression_section.dart:145-166,406-447` vs grep ONNX/classification/burst in `web_ui/src/components/VoiceMediaSettings.tsx` → 0 | inventory diff + code | open |
| 14 | Slash cheat-sheet omits `/afk` and `/image` (desktop catalog has 17 commands, web sheet lists 15) | `lib/services/chat/chat_command_handler/slash_command_catalog.dart:37-123` vs `web_ui/src/components/ChatComposer.tsx` | inventory diff + code | open |
| 15 | Suspects pending deep verify: (a) group per-speaker "Regenerate main character (removes the NPC's reply)" variant; (b) persona JSON import/export app-bar actions; (c) Models-folder ops (Change folder / Open in File Manager) on /models | desktop: `message_bubble.actions.dart:177`, `user_persona_page.dart` AppBar, `model_manager_page.dart` | inventory diff | suspect |

## Waifu Coder ruling (#6), 2026-11-12 — DESKTOP-ONLY, permanent

Maintainer ruling: **Waifu Coder remains Dart-app only.** It is not queued for
a web port and must not be counted as drift in future parity audits; the web
two-mode toggle is the intended shipped behaviour. Decision also unblocks this
PR (it never gated it): Rationale:

1. It is not a control gap — it is a missing **feature**: no web facade at all
   (`lib/services/web/` has zero waifu endpoints) plus ~5,900 lines of UI in
   `lib/ui/waifu/`. Porting it is an SOW of its own, like the AI Character
   Creator and Porch Stories were.
2. It is a local-process feature (private `opencode serve` on loopback,
   filesystem drops, skill folders). The web story is "remote-control the
   host's coder", which needs its own design pass, not a parity patch.
3. The web degrades honestly today: `HomeModeToggle` is a clean two-mode
   control; nothing is broken or half-drawn. This fits the ⏳/❌ legend of
   dev-notes/web-parity.md, so the parity guard's silence is acceptable here.

Action: add a `❌ Waifu Coder` row to `dev-notes/web-parity.md` ("out of
scope — confirmed no-go, desktop-only by rulings").


## Screenshot policy for PR screens (maintainer, 2026-11-12)

GitHub PR screenshots must be **purely synthetic SFW content** — never the
maintainer's live chats or library art. Recipe: throwaway characters with
neutral/initials avatars, short synthetic SFW exchanges, captured from the
web at 1440px and 390px via the scripted browser; desktop app shots are
taken by the maintainer (the agent shell has no screen-recording rights).
Delete the throwaway characters/chats after capture and say which were used.

## CI triage, 2026-11-12 (heads 73aae5f8b → d173f58be)

- **Tests (unit + integration) 2/4 — ours, fixed.** `one_ui_parity_test.dart:869`
  "the exemption tables name ids that exist" went red because the cast fix
  removed `'cast'` from web `WIDE_DEFAULTS` while `_webOnlySections`
  (test/hygiene/one_ui_parity_test.dart:37) still carried the exemption that
  had excused the drift. Exemption retired in `d173f58be` (label
  `approved-test-change`). Lesson: when a parity fix deletes a section, the
  guard's exemption tables must lose the row in the same commit.
- **Playwright "WebUI in real browsers" — pre-existing, NOT this PR.**
  Failure: `/models: the dialog opened by "📄 Model card" has no Close/Cancel
  and ignores a tap outside` (e2e/support/fixtures.ts:155 via sweep).
  `ModelCardDialog.tsx` (commit `077b3c4b6`) predates the PR and is already
  on Rawhide — and it *does* render a Close action, so the sweep likely hit a
  different "📄 Model card" trigger on /models or misattributed after a
  mid-sweep browser crash (`controls seen: 0`). Rawhide's own latest CI
  (`89e0f393`) fails the same Playwright job. File separately; do not widen
  PR 5 for it.

## Playwright flake pattern on head 6621b8be2 (three runs, three different failures)

1. `sweep` — /models "📄 Model card" dialog usability flag (also red on
   Rawhide `89e0f393`).
2. rerun-1 — serial `Stories from group chats` @serial: first attempt
   timeout `waiting for locator('.chat-view')`.
3. rerun-2 — serial `a member's start in the group's new chats saves`:
   `HTTP 404 from GET /api/groups/group_<fresh>/stats` — the route exists
   (`lib/services/web/routes/group_routes.dart:47`) and 404s only for
   unknown ids: the page polled stats after the test deleted its group.

All three surface through the same `crashRetry` guard
(`web_ui/e2e/support/fixtures.ts:155`), which turns any first-attempt
non-crash error into a failure. None involve the cast roster or the
sidebar section list; the 208 other tests passed every run. Morning
triage belongs to the serial-block + stats-poll race on phone-webkit,
not to PR 5's diff.

## Playwright flake — fourth run (head e0e1107eb, run 43195224027)

Fourth run, fourth different failure, all [phone-webkit]: this time
`journeys.spec.ts:502 the creator's Greetings step` caught
`HTTP 500 from GET /api/characters/<fresh>/avatar` (209 passed).
The route is healthy on the local backend (200 x3 on an existing
character). The runner log is flooded with
`ImageGen: switchLocalModel failed … 127.0.0.1:9/sdapi/v1 … Connection
refused` — port 9 (discard): local imagegen is not configured in CI, so
avatar/expression synthesis 500s intermittently in the sandbox, and the
crashRetry/page-problems guard turns any such 5xx into a test failure.

Conclusion (four runs, four endpoints, one surface): pre-existing
phone-webkit serial-block flakiness from an unconfigured imagegen in CI
+ the strict page-problems guard — already red on Rawhide `89e0f393`,
not caused by PR 5's diff. Recommend a separate issue: configure or
stub imagegen in the e2e sandbox, and/or exempt imagegen-dependent
endpoints from the page-problems guard.

## stats-poll race root-caused and fixed (run 43389757090, phone-webkit)

Trace forensics (run 43389757090; both trace files share one worker clock):
the teardown `POST /api/groups/<fresh>/delete` completes at mono 196765.2,
the editor's stats GET answers 404 at mono 196804.9 — ~40 ms later. The GET
is real, not a webkit unload ghost: saving the member editor returns to the
Edit group page (`CharacterEditPage.tsx` save-then-navigate), whose mount
refetches `/api/groups/<id>/stats` (`GroupEditPage.tsx` stats card); the
journey's `finally` deletes the group mid-refetch, so `getById` is already
null and the route's 404 is correct — the strict monitor rightly flags it.

Fix: `openRoute(page, '/')` before the teardown delete in the two journeys
that end in the group editor (2339, 2568 as of this commit). Home has no stats card, so
nothing polls the deleted group. e2e-only; no monitor seam, no backend
semantics change.

Side finding (latent, NOT this flake): `GroupChatRepository._load()` clears
the in-memory list before awaiting the DB read, so `getById` answers null
for live groups during any rebind/duplicate reload. An atomic swap hardens
the read side but can drop a concurrent `save()` on the write side; if
pursued, fix both halves together.

Validation gate: `--repeat-each=20` over both tests, phone-webkit, guard
active, against the harness sandbox.

## FPAI_E2E_HOLD teardown timeout is benign (browser_test.dart:243-246)

A hold-mode session "fails" after `touch e2e/.auth/stop` with
`TimeoutException: Timed out after 20s waiting for in-flight screen
refresh to finish during shutdown` (thrown twice in one run, flagged
"Multiple exceptions (3)"). The cleanup races the external client's last
frames; stopping via the stop file at an arbitrary moment makes the
timeout likely. The CI path never uses hold mode and its cleanup lands
inside the window (web-e2e green on `ef5bf0489`+). A red hold teardown
after a green external Playwright run is not a product failure — read
the Playwright summary, not the harness verdict.
