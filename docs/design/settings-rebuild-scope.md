# Settings rebuild — scope and verified inventory (PR 7, chunks 7a–7d)

Status: scoped 2026-11-13 against Rawhide head `3fad54abf`. This is the
work file for **PR 7 of [one-chat-ux.md](one-chat-ux.md)** (bumped from
PR 8; closes `dev-notes/drift-ledger-726.md` ledger #5, #13, #14, #4, #15).
Every file:line here was read this sitting — do not re-sweep, and do not
cite these lines from memory after a rebase: re-verify.

## 1. Reference UI (binding for 7a/7b)

The PWA Settings must match the **Dart Settings window as it ships**, not
the old six-flat-section web page. Maintainer screenshot reference
(2026-11-13, dark theme): the Dart window shows the seven-tab bar
`General · Appearance · Porch Life · Generation · Voice & Media ·
Backend · Advanced` and a General tab built of grouped subsections with
accent-colored headers, each control carrying its own explanation line:

- chat group (unlabeled): *My messages on the right*, *Follow streaming
  replies*, *Auto-check for Updates* + a full-width
  *Check for Updates Now* button, *Spell Check Language* dropdown.
- **Porch Life** group: *18+ themes* switch + the pointer card
  ("The Realism Engine, passage of time, weather, the Journal … all live
  in the Porch Life tab now") —
  `lib/ui/settings/tabs/general_tab.dart:167-197`,
  `lib/ui/settings/tabs/general_tab/porch_life_pointer_card.dart`.
- **Fallback system prompt** group: title with a *Not saved* status chip,
  explanation, a *Load a saved prompt…* dropdown + delete action, the
  prompt field, then *Save as new…* and *Reset to built-in* —
  `lib/ui/settings/tabs/general_tab.dart:199-200`.

This structure is already in the repo at head. The parity target is
control-for-control, same groups, same order, same helper text tone;
layout adapts to phone. Note PRs #716/#719 propose further redesigns of
these same tabs — see §4.

Tab list in code: `lib/ui/pages/settings_page.dart:230-280`
(`DefaultTabController(length: 7)`).

## 2. Chunks

Four draft PRs on Rawhide, the PR 1a/1b precedent. Each carries its own
`## Hand-check`, `## Screenshots` (see §8), manifest updates, and desktop
+ web in one change per the One UI rule.

### 7a — structure (ledger #5, layout only)

Web Settings (`web_ui/src/pages/SettingsPage.tsx`, 744 lines) becomes
**seven sections in desktop tab order**. Today it has six: `general`,
`porch-life`, `generation`, `voice-media`, `backend`, `advanced`
(`SettingsPage.tsx:410,438,443,478,483,649`) — Appearance is folded into
general.

- New `data-section="appearance"`; the chat-appearance group
  (`SettingsPage.tsx:413-420`: MessageSide, FollowStreaming,
  AppearanceSettings, ReadingSize, BubbleOpacity, ChatColors) and the
  ambient/scene-sound/mood blocks move from general into it, in desktop
  Appearance order (see §3 inventory).
- General matches the §1 reference: grouped sub-headers (Porch Life
  group with the 18+ themes switch + pointer card; Fallback system
  prompt card with status chip, load/save-as-new/reset/delete). Check
  what prompt plumbing `/api/settings` already offers before wiring the
  prompt card (`lib/services/web/facade/settings/`).
- No new host-backed controls in 7a. If a control has no web API key
  yet, it waits for 7b — do not fake it with localStorage in this chunk.
- Parity: rebuild the `sections` list in
  `docs/design/settings-parity-manifest.json:11` (currently the six
  above), move the affected control entries' `section` fields, and land
  the guard changes in the same commit:
  `test/hygiene/settings_parity_manifest_test.dart:31-69` and
  `web_ui/src/pages/SettingsPage.parity.test.tsx:138-186`. Lesson from
  the ledger's CI triage: exemption tables and deleted sections die in
  the same commit (`approved-test-change` with the reason).
- `SettingsPage.tsx` is over any split threshold already: new sections
  go into new component files, following the existing per-card pattern.

### 7b — host theme controls (ledger #5, the named five)

Desktop Appearance tab inventory (`lib/ui/settings/tabs/appearance_tab/`):

| Control | Dart | Web today |
|---|---|---|
| Theme gallery, 8 `AppThemeId` themes, mini-chat previews | `theme_card_grid.dart:29`, `theme_preview_card.dart:25`, enum `lib/ui/theme/themes/app_theme_id.dart:29` (porch, slate, graphite, midnight, evergreen, plum, harbor, high_contrast) | missing |
| Mode Dark/Light/System | `appearance_tab.dart:53-60` | web has a per-device 4-way choice + dark switch (`AppearanceSettings.tsx:232-254`) |
| Accent picker: theme accent + swatches + free color, readability-adjusted | `appearance_tab.dart:61`, `accent_picker_row.dart:30-98` | missing |
| UI font: Inter/System/Atkinson/Literata | `appearance_tab.dart:62-69`, enum `lib/ui/theme/appearance_options.dart:36-40` | missing |
| Corners: Sharp/Default/Round | `appearance_tab.dart:70-77`, enum `appearance_options.dart:56-59` | missing |
| Reset accent, font and corners | `appearance_tab.dart:81-89` | missing |
| Ambient scene / pause-effects (only when Story Weather on) | `background_weather_section.dart:33` | present (`AppearanceSettings.tsx:255-316`) |
| Scene sound + volume | `scene_sound_controls.dart:31` | present |
| Reading size slider (0.7–2.0) | `chat_appearance_section.dart:61-68` | present (`ReadingSizeSettings.tsx:45-56`, device-local) |
| Mood on the character + Drama | `mood_on_character_controls.dart:32` | present (`AppearanceSettings.tsx:317-348`) |
| 6 chat colors | `chat_appearance_section.dart:75-129` | present but device-local localStorage (`web_ui/src/chatColors.ts:32`) vs host prefs — see §6 |
| Chat Font dropdown (18 fonts, ''= UI font) | `chat_appearance_section.dart:34-53,134-192` | missing — see §6 |
| "Use the theme's chat colors" reset | `chat_appearance_section.dart:194-202` | web has "Reset to defaults" to its own local defaults |

Host work:

- Settings snapshot gains `themeId`, `accent`, `uiFont`, `corners`; the
  writer gains matching keys; both broadcast on `settings_changed`
  (`lib/services/web/facade/settings/settings_snapshot.dart:217-233`,
  `settings_writer.dart:92-135`, `lib/services/web/host/web_live_relays.dart:414-419`).
  None of the four keys exists in the web API today (verified: no hits in
  snapshot, writer or routes).
- Dart setters already exist — do not write new storage:
  `lib/services/storage/settings/appearance_settings.dart:168`
  (`setTheme`), `:185` (`setAccentOverride`), `:196` (`setFont`),
  `:203` (`setCorners`), `:256-264` (`resetCustomisations`). Prefs keys:
  `app_theme`, `accent_override`, `ui_font`, `ui_radius`.
- The snapshot already ships resolved dark/light token maps per theme
  (`settings_theme.dart:26`): the web paints the host-resolved palette.
  No theme math, no accent adjustment duplicated in TypeScript.
- Theme gallery previews on web render from the same token maps.
- Free-color accent: accept the same normalization the Dart picker
  writes; validate server-side; invalid → 400 with a message the web
  shows inline.

Multi-surface behavior is ruled in §3.

### 7c — Voice & Media (ledger #13)

Web has two switches only (`web_ui/src/components/VoiceMediaSettings.tsx`,
77 lines; facade writes `ttsEnabled`/`sttEnabled` only,
`lib/services/web/facade/voice_facade.dart:69-71`). Desktop tab order:
`lib/ui/settings/tabs/voice_media_tab.dart:55-79` — TTS → STT (+voice
call settings) → Photo understanding → Expressions → Image-gen enable →
legacy cleanup.

Missing on web, with Dart evidence:

- STT: Whisper model choice + download with progress
  (`stt_section.dart:133-240`), mic device list + refresh
  (`stt_section.dart:280-340`, ruled §5), auto-send transcription
  (`voice_call_settings.dart:405-411`).
- Voice call settings (call model `voice_call_settings.dart:240-290`,
  buffer `:300`, system prompt): **stay desktop** — voice call is
  1:1-desktop-only forever (one-chat-ux ruling 9). Pin `❌` in
  `dev-notes/web-parity.md`, don't port.
- Photo-understanding card (`lib/ui/settings/widgets/photo_understanding_card.dart:34`,
  self-hiding until the caption model is installed).
- Expression controls (`expression_section.dart`): enable `:96-107`,
  classification LLM/ONNX/Manual `:158-166`, ONNX download `:214-216`,
  display mode `:216-224`, re-roll `:249`, emoji burst `:277` + size
  `:300-323`, fallback `:357-375`.
- Image-gen enable toggle (`lib/ui/settings/widgets/image_gen_enable_section.dart:73-96`).

Cost is backend: extend `/api/voice/settings` (`voice_routes.dart:30-33`)
with the expression/whisper/photo/imagegen keys, and add download
progress (poll endpoint or relay events — Whisper and ONNX downloads both
report progress on desktop). Verbs for expression packs exist
(`expression_pack_routes.dart:15-46`) but nothing reads or writes
`expressionEnabled`/classification/whisper model/mic devices/
`autoSendTranscription` over `/api` today (verified: zero hits).
Sketch the progress plumbing before building.

### 7d — small fills + suspects (ledger #14, #4, #15)

- Slash sheet: the web `SLASH_COMMANDS` array
  (`web_ui/src/components/ChatComposer.tsx:27-43`) hand-copies 15 of the
  catalog's 17 (`lib/services/chat/chat_command_handler/slash_command_catalog.dart:37-119`);
  `/afk` and `/image` are missing from the sheet while dispatch is
  shared (`send_spine.dart:315-322`). Preferred fix: serve the catalog
  from `/api` and render the payload, so the sheet can never drift
  again; fallback is the two lines. (Decision: §6.)
- Folder tiles (ledger #4): web `FolderCard` is a landscape 📁 row
  (`web_ui/src/components/library/LibraryCards.tsx:97-147`,
  `web_ui/src/styles/library-cards.css:51-54`); desktop is a portrait
  tile with a 2×2 montage of up to 4 member portraits +
  "N characters · M groups"
  (`lib/ui/pages/home/cards/folder_grid_card.dart:66-87,154-231`).
  `GET /api/folders` ships counts only (`character_facade.dart:292-305`);
  extend the payload with preview member avatars (ids + avatarVersion,
  same shape characters and groups already carry,
  `character_facade.dart:173-177`, `group_facade.dart:100-135`) and
  reuse the existing avatar URLs
  (`/api/characters/<id>/avatar`, `/api/groups/<id>/members/<memberId>/avatar`).
  The 2×2 grid CSS pattern already exists (`.group-art`,
  `library-cards.css:43-49`).
- Suspects (#15), each ending in a fix or a pinned ◑/❌ row in
  `dev-notes/web-parity.md`: (a) group per-speaker "Regenerate main
  character (removes the NPC's reply)" variant
  (`message_bubble.actions.dart:177`); (b) persona JSON import/export
  app-bar actions (`user_persona_page.dart`); (c) models-folder ops on
  `/models` (`model_manager_page.dart`).

## 3. Ruling needed — web theme becomes host-wide (reverses the ❌)

`dev-notes/web-parity.md:118-125` marks Theme (among others) `❌` "no-go"
for web. The drift ledger and the one-chat-ux poke script both require
"changing theme or accent on the web changes the desktop too" — one
shared prefs store, so **any browser tab changes every surface**, other
browsers included. Proposed ruling: keep the ledger's line — theme,
accent, UI font and corners are host settings, all surfaces follow
within a second over `settings_changed`; flip that ❌ row to ✅ in 7b
with this doc as the justification. Per-device taste (reading size, chat
colors, the device 4-way dark choice) stays device-local where it already
is. Needs the maintainer's explicit OK before 7b merges.

## 4. Prep — before the first 7a commit

1. **Dispose of PRs #716–#719** (all OPEN, redesign the same surfaces):
   #716 general settings cards/typography, #717 web general option-A
   stacked prompt cards, #718 appearance 4-tier hierarchy + color
   matrix, #719 generation dual-column studio console. 7a builds on
   whatever lands; decide merge/close/absorb per PR, in that decision's
   wake re-verify §1 and §2 line references.
2. **Land or park the in-flight tree** (group-editor edits:
   `lib/ui/pages/edit_group/*`, `web_ui/src/pages/GroupEditPage.tsx`,
   `test/services/group_editor_fields_test.dart`) — 7a must not carry
   them.
3. Ruling §3 (theme host-wide) and §5 (mic devices) recorded.
4. `dev-notes/web-parity.md`: pre-stage the ✅/◑/❌ row changes 7a–7d
   will need so the parity doc never lags a shipped chunk.

## 5. Ruling needed — microphone devices

Desktop lists the **host's** input devices (`stt_section.dart:280-340`).
A browser can only enumerate the **client's** devices, and the host's
capture happens on the host machine. Proposal: mic device selection
stays `⚙️` desktop-only (engine/hardware setup, same legend as the rest
of first-time setup); the web gets everything else in 7c. Maintainer's
call before 7c.

## 6. Open decisions (small, pick inside the chunk)

- Slash catalog: serve from `/api` (kills the drift class) vs add two
  lines. Recommend serving.
- Chat Font dropdown + "use the theme's chat colors": desktop-only, or
  join 7b? Ledger #5 doesn't name them; §1 reference is tabs, not
  this control. Either port in 7b or pin `◑` so the next audit doesn't
  rediscover it.
- Web chat colors are device-local (`chatColors.ts:32`) while desktop's
  are host prefs. Keep the split (pin `◑`) or move web to host keys.
  Keep-the-split is cheaper and matches per-device taste in §3.

## 7. Parity and test wiring (every chunk)

- New/changed controls land in `docs/design/settings-parity-manifest.json`
  with their section pin, `dartMarker`, `webMarker`; both guards
  (`settings_parity_manifest_test.dart`, `SettingsPage.parity.test.tsx`)
  pass in the same commit; edited guards take `approved-test-change`.
- 7a: rebuild the `sections` list to seven and re-pin moved controls in
  one commit (CI lesson: exemptions die with the section).
- Facade changes get Dart tests (snapshot keys, writer validation,
  broadcast); web components get vitest per the existing pattern
  (`AppearanceSettings.*.test.tsx` family).
- `wc -l` every grown Dart file (500 cap) + `flutter test test/hygiene/`
  before any push touching `lib/`.

## 8. Delivery checklist (every chunk PR)

- Draft PR on Rawhide; `## Hand-check` lines; One-UI: desktop + web twin
  in the same change.
- Screenshots: purely synthetic SFW content, web at 1440px and 390px,
  throwaway characters/chats deleted after capture and named in the PR;
  desktop shots come from the maintainer. **Upload to GitHub —
  relative `docs/screenshots/` links rendered broken twice** (Error
  Book, 2026-11-13).
- Poke scripts: one-chat-ux.md §"Poke scripts" PR 7 lines.
