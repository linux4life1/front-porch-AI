# Settings rebuild — scope and verified inventory (PR 7, chunks 7a–7d)

Status: scoped 2026-11-13 against Rawhide head `3fad54abf`. Ruled the same
day: theme is **host-wide** (§3), voice-call and mic/host-capture controls
are **desktop-only** (§5). **7a merged** (#729, Rawhide `94ab08b97`).
**7b re-scoped and ruled 2026-11-13 against `94ab08b97`** (§2-7b): slim
gallery previews, bundled Inter/Atkinson, corners token-only, auto-check
keys in, chat font + chat colors folded in, #716–#719 ignored. This is the
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
  Consequence built as noted: the desktop General *Auto-check for
  Updates* row has no key on `/api/settings` (verified: no update code
  in `settings_snapshot.dart`/`settings_writer.dart`), so it waits for
  7b; the page carries a comment where it will sit.
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

### 7b — host theme controls (ledger #5) — re-scoped on `94ab08b97`

Maintainer rulings (2026-11-13; binding): gallery previews serve a **slim
host-resolved token set** per theme; the web **bundles Inter + Atkinson
Hyperlegible Next woff2** so UI fonts paint their real face; **corners drive
the token-driven surfaces only** (`--radius*` + new controls follow), the
literal radii migrate later — pin ◑; the **Auto-check for Updates keys ship
in 7b** (7a's promise, `SettingsPage.tsx:459-460`); **#716–#719 are
ignored** — 7b branches Rawhide and re-pins markers if one lands; the
**Chat Font and the six chat colors join 7b** (§6 closed; this supersedes
§3's device-local ruling for chat colors only).

Desktop Appearance inventory, re-verified at `94ab08b97`:

| Control | Dart | Web today |
|---|---|---|
| Theme gallery, 8 `AppThemeId`, mini-chat previews | `appearance_tab.dart:47`; `theme_card_grid.dart:29-62`; `theme_preview_card.dart:107-153`; enum `app_theme_id.dart:29-42` | missing; the slot exists — `theme-group` at `SettingsPage.tsx:524-527` names 7b in its comment |
| Mode Dark/Light/System | `appearance_tab.dart:53-60` | partial: `ThemeModeSettings.tsx` (89 lines) writes `darkMode`, which collapses System to Dark/Light on the host (`settings_writer.dart:92-94` → `ui_settings.dart:306-308`) |
| Accent: theme default + 12 swatches + free color, readability note | `appearance_tab.dart:61`; `accent_picker_row.dart:52-84`; swatches `accent_swatches.dart:24-37`; dialog `color_picker_dialog.dart:38-145` | missing |
| UI font Inter/System/Atkinson/Literata (segmented) | `appearance_tab.dart:62-69`; enum `appearance_options.dart:36-53` | missing; body font is hard-coded (`base.css:124`; Figtree served, `studio.css:14-17`) |
| Corners Sharp/Default/Round (scales 0.25/1/1.6) | `appearance_tab.dart:70-77`; enum `appearance_options.dart:56-72` | missing; 372 literal `border-radius` uses vs 3 vars (`base.css:44-46`) |
| Reset accent, font and corners | `appearance_tab.dart:81-89` → `resetCustomisations` `appearance_settings.dart:257-265` | missing |
| Chat colors, six, per brightness | `chat_appearance_section.dart:75-129`; setters `ui_settings.dart:209-275` | device-local (`chatColors.ts:32`) — **moves to host keys in 7b** |
| Chat Font dropdown, 18 Google Fonts, `''` = UI font | `chat_appearance_section.dart:34-53,134-192`; `setGlobalChatFontFamily` `ui_settings.dart:301`; runtime-loaded via `google_fonts` (`pubspec.yaml:44`) | missing (the web's 3-option per-chat font, `ChatThemeSettings.tsx:29`, is unrelated) |
| Use the theme's chat colors | `chat_appearance_section.dart:194-202` → `resetChatColors` `ui_settings.dart:276` | web "Reset to defaults" goes to its own local defaults |
| Reading size / mood / ambient / scene sound / bubble opacity | 7a rows | present; device-local taste stays (§3) |

Confirmed ground (re-read this sitting):

- No `themeId`/`accent`/`uiFont`/`corners` keys in snapshot, writer, relays
  or routes. The only theme key is the resolved `theme` wire
  (`settings_snapshot.dart:215-217`, `web_live_relays.dart:417`) and it is
  what paints (`appTheme.ts:86-111`); 7b **adds to it, never replaces it**.
- `webThemeWire` ships only the *selected* theme's maps
  (`settings_theme.dart:26-30`, `web_theme_tokens.dart:41-48`) — a gallery
  cannot preview 8 themes from it. Host preview source:
  `palettesFor(theme)` `appearance_settings.dart:96`.
- Dart setters all exist (`appearance_settings.dart:168-208,257-265`);
  prefs `app_theme`/`accent_override`/`ui_font`/`ui_radius` (beta-prefixed
  in prerelease, `settings_base.dart:44-45`). Traps: `UiCorners.standard`
  wires as `'default'` (`appearance_options.dart:58`) — round-trip keys,
  not enum names; accent is `#RRGGBB` uppercased with alpha forced
  (`appearance_settings.dart:186-192`, `accent_fit.dart:145-154`) — never
  feed an `rgba(...)` token to `setAccentOverride`; invalid values are
  **silently ignored** (`:97-100` precedent) — no per-key 400s (a malformed
  `ambientScene` never 400s either; the earlier "invalid → 400" note dies
  here).
- Desktop changes already reach the relay: setter → `notify()`
  (`settings_base.dart:50`) → `StorageService.notifyListeners`
  (`storage_service.dart:352`) → the debounced broadcast
  (`web_live_relays.dart:426`). No new stream.
- Line caps: `web_live_relays.dart` is **499/500** — 7b spends exactly one
  line there, a spread `...appearanceWireFields` (the `sidebarWireFields`
  precedent at `:420`), the extension living in `settings_theme.dart`.
  `settings_writer.dart` is **472** — the new branches do not fit; split
  `settings_appearance_write.dart` like `settings_sidebar_order.dart`
  (precedent comment `settings_writer.dart:137-139`).

Host work:

1. `settings_theme.dart` (30 lines, the file whose contract is exactly
   this): add raw-pick keys `themeId`, `accent` (`null` | `#RRGGBB`),
   `accentAdjusted`, `uiFont` + `uiFontFamily`, `corners` (key + scale),
   `chatFont` + the served 18-entry `chatFontChoices` catalog (shared with
   the desktop dropdown as `kChatFontChoices`), the six `chatColors` **as
   the chat paints them** (pick, else theme default) plus
   `chatColorDefaults` so the PWA leaves an unpicked role to the theme and
   light mode keeps its own ink, and `autoCheckForUpdates`; add
   `themeGallery` — 8 × `{key,label,tag,blurb}` + the slim preview set per
   brightness, exactly the 9 tokens the mini-chat draws (bg, surface, card,
   border, text, muted, user-bubble, ai-bubble, porch-amber) via
   `WebThemeTokens.resolve` + `palettesFor`; serve `accentSwatches` (the
   12 hexes) so the web hard-codes nothing; add the
   `appearanceWireFields` extension for the relay. Slim payload ≈ 3–4 KB
   per snapshot/`settings_changed` — accepted. (Design change from the
   first draft, recorded 2026-11-13: raw `null` picks need new getters in
   `ui_settings.dart`, which sits at 499 lines; the resolved+defaults pair
   gives the web the same information. Known edge: a pick that equals the
   theme's own colour reads as unpicked — visually identical.)
2. Snapshot: mount the block beside `theme` (`settings_snapshot.dart:215`);
   plumb `UpdateService` into `SettingsFacade`
   (`settings_facade.dart:55-65`) — state at `update_service.dart:99,191`.
3. New `settings_appearance_write.dart`, called from `update()` like
   `applySidebarOrderWrite`: enum-key-gated `themeId`/`uiFont`/`corners`
   (the `:98-99` pattern), `accent` via `parseAccentHex` (`''` → null),
   `chatFont` gated to the catalog, per-key `chatColors` hex-or-null,
   `resetAppearance: true` → `resetCustomisations()`, `resetChatColors:
   true` → `resetChatColors()`, `autoCheckForUpdates` bool. POST already
   returns the full snapshot (`settings_routes.dart:127`), so every picker
   refreshes free; routes stay GET/POST only.
4. Relay: the one spread line, nothing else.

Web work:

5. `useDesktopTheme.ts` + `api/ws.ts` carry the new keys; `appTheme.ts`
   paints `--ui-font` and `--radius*` (`calc(base × host scale)` — scaling
   the web's own tokens, not palette math) and the resolved chat font as
   default `--chat-font` (per-chat `ChatThemeSettings` still overrides).
   Paint-only, no theme math (that file's header rule).
6. New components in the `theme-group` slot: `ThemeGallerySettings.tsx`
   (reuse the `.theme-preset-card` pattern, `ChatThemeSettings.tsx:168-191`;
   preview colors inline from the gallery payload — `colorLiterals.test.ts`
   has an **empty baseline**, no hex in new CSS), `AccentPickerSettings.tsx`
   (theme-default swatch + served swatches + native `<input type="color">`),
   `UiFontSettings.tsx` (`.mode-seg` radiogroup), `CornersSettings.tsx`,
   the reset row; rewrite `ChatColorsSettings.tsx` to host round-trip
   (keep the dialogue/action contrast mirror, `chatColors.ts:167-192`) and
   add the Chat Font select from the served catalog. House pattern each:
   own `/api/settings` fetch + `settings_changed` socket, optimistic write
   with rollback, `SettingRow`. Chat fonts load from the Google Fonts CDN
   at runtime like the desktop's `google_fonts`; UI fonts never — Inter +
   Atkinson woff2 join `web_ui/public/fonts/` beside Literata.
7. Do not inline anything in `SettingsPage.tsx` (822 lines). Corners'
   literal-radius migration is a follow-up; pin ◑ rows in
   `dev-notes/web-parity.md` (partial corners; per-character chat-font
   override `ui_settings.dart:495-497` is desktop-side).

Parity + tests:

8. Manifest (`settings-parity-manifest.json`, sections unchanged): new
   `controls` entries, `section: "appearance"`, group `theme` for the five
   theme controls and `chat-appearance` for chat font/colors/reset, with
   verified dartMarkers — `"ThemeCardGrid()"` (`appearance_tab.dart:47`),
   `"AccentPickerRow()"` (`:61`), `"label: 'UI font'"` (`:64`),
   `"label: 'Corners'"` (`:72`), `"Reset accent, font and corners"`
   (`:88`) — plus `SettingsPage.parity.test.tsx` stubs per new component
   (it mocks sub-panels to marker text, `:38-49`; un-stubbed `api.get`
   leaks); `chatColors` entry loses its device-local wording. Edited guards
   take `approved-test-change`. If a #716–#719 PR lands mid-flight,
   re-pin markers in the same change.
9. Dart facade tests: snapshot keys + gallery shape, writer gating and
   normalization (uppercased accent, corners `'default'`, bad enum
   ignored-not-400), relay spread carries the picks, auto-check round
   trip. Vitest per new component (read/post/rollback/follow, the house
   family); `appTheme` tests for `--ui-font`/`--radius*`/`--chat-font`
   paint. One e2e journey: set gallery theme, accent, font, corners and a
   chat color on the web → tokens repaint, survives reload, restore in
   `finally`. `capture-settings-7b.mjs` twin of 7a's script; screenshots
   uploaded to GitHub, not linked (Error Book, 2026-11-13).
10. Poke: one-chat-ux PR 7 line — Settings open side by side; changing
    theme/accent on the web changes the desktop, every session follows
    within a second.



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

## 3. Ruled 2026-11-13 — web theme is host-wide (❌ reversed)

`dev-notes/web-parity.md` marked Theme `❌` "no-go" for web. Maintainer
ruled: **theme, accent, UI font and corners are host settings** — one
shared prefs store, changing theme on the web changes the desktop and
every open session follows (within a second over `settings_changed`).
The parity doc now carries a ✅ row for the host-wide dark mode (live
since 7a) and an ⏳ row for the gallery/accent/font/corners that 7b
ships. Per-device taste (the 4-way device choice, reading size) stays
device-local where it already is. Chat colors moved out of that list into
host keys by the 7b ruling (2026-11-13, §2-7b).

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

## 5. Ruled 2026-11-13 — voice/mic stays desktop

Maintainer ruling: the browser round trip makes interactive voice
unreasonable off desktop. Recorded in `dev-notes/web-parity.md`:
voice call `❌` forever (already ruling 9 of one-chat-ux); mic device
list + Whisper model download + engine setup `⚙️` desktop-only — the
host captures on the host machine and a browser only sees its own
devices. Existing web TTS playback and upload-based STT dictation stay
as they are (✅ rows). What 7c still ports: expression controls,
photo-understanding card, image-gen toggle, auto-send transcription —
pure host settings with no round-trip cost.

## 6. Decisions — resolved 2026-11-13

- Slash catalog (7d): serve from `/api` (kills the drift class) vs add two
  lines. Recommend serving; still open for the 7d sitting.
- Chat Font dropdown + "use the theme's chat colors": **join 7b**
  (maintainer ruling) — `chatFont` + the six chat-color keys ship in
  §2-7b, not a ◑ pin.
- Web chat colors: **move to host keys in 7b** (maintainer ruling); the
  dialogue/action contrast mirror (`chatColors.ts:167-192`) stays web-side.
- Wire validation: invalid enum/accent values are silently ignored, the
  house pattern (`settings_writer.dart:97-100`); the earlier
  "invalid → 400" note is dead.
- #716–#719: **not ours, still drafts — pretend they don't exist**; 7b
  branches Rawhide and re-pins manifest markers only if one lands first.

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
