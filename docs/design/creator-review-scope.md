# AI creator Review step — scope and verified inventory (PR 8d, one PR)

Status: scoped 2026-11-15 against Rawhide head `c2561ff19`. Maintainer
ruled the same sitting: **Vision QC is held back** (desktop-only, §3);
**everything else ships exactly as the Dart app has it** — this is a
port, not a redesign (§1). This is the work file for the web port of the
AI Character Creator's Review step (`dev-notes/web-parity.md:63` ⏳ row,
`dev-notes/drift-ledger-726.md` ledger #12 remainder). Every file:line
here was read this sitting — do not re-sweep, and do not cite these
lines from memory after a rebase: re-verify.

**Built** 2026-11-15 on `feat/pr8d-creator-review` in three commits (host
seed, host avatar routes, web Review step + rail). Verified: `flutter
test test/services/web/ test/hygiene/` (871 passed), `npm test` (1694
passed), `npm run lint`, `npm run build`. The browser journeys were
updated to the new flow but the Playwright suite needs the Flutter host
harness and was not run locally.

## 1. Reference UI (binding)

Reference shots: `docs/screenshots/pr8d-creator-review/` (maintainer
desktop captures; `desktop-review-light-wide.png` in, 2026-11-15).

What the light-wide shot pins (verified against the code, no drift):

- Step rail shows Review as the numbered final step after Realism.
- Left rail header `PORTRAIT — PICK A SOURCE`; the tri-state renders as
  three chips with Upload selected; `Generate` disabled; the no-engine
  banner copy is `Generate is unavailable — no image engine is set up.
  Configure one, or upload images instead.` with a `Set up` action.
- Upload mode shows the portrait well + `＋` well, caption `First image
  is the portrait; add more as gallery looks, or tag one with an emotion
  to make it an expression image.` (confirms the 1-well pack-off shape,
  §2-8d-B.4).
- The expressions card is `EXPRESSIONS — INDEPENDENT OF THE PORTRAIT
  SOURCE`: `Generate pack` pill switch off, explainer `Upload
  expression images instead: tag uploads above with an emotion, or
  import an emotion-named ZIP sprite pack.`, then `Import ZIP`. So
  without an engine only the ZIP path is live — Vision QC's absence is
  doubly invisible here (§3).
- Name `Porchie` centred, then the read-only tag chips
  (`tsundere`, `vampire`, …) — §2-8d.4/5 match.
- Right column: intro paragraph matches `creator-ui-spec.md:158-160`;
  cards are `Description` + subtitle `Who they are, as the card will
  carry it`, `Personality` + `How they act and speak`, `Scenario` +
  `Where the first chat starts` — subtitle copy to add to §2-8d.2; each
  card carries a fullscreen/expand affordance top-right (new, see
  §2-8d.2); macro tokens (`{{user}}`, `{{char}}`) render tinted.
- Nav is `Back` + amber `Save & Finish` with a trailing check.

The PWA must match the **Dart wizard as it ships**:

- Step shell and copy: `lib/ui/character_creator/steps/review_step.dart`
  (295 lines) and the canonical copy in
  `docs/design/creator-ui-spec.md:155-170` (title `Review`, the intro
  sentence, the two rewrite cards' wording, `Save & Finish`).
- Left rail: the SHARED `AvatarGenerationPanel`
  (`lib/ui/avatar_creation/avatar_generation_panel.dart`, 223 lines) —
  the same widget the manual creator's Portrait step uses; port its
  behaviour, do not improvise a web-only avatar surface.
- Nav + save: the wizard shell owns Save & Finish
  (`lib/ui/pages/character_creator_page.dart:275-278` label, `:176-211`
  `_saveAndFinish`), not the step body (`review_step.dart:31-34`).
- **Layout correction (2026-11-15)**: the Dart wizard has **no phone
  layout** — no `android/`/`ios/` targets, no breakpoints in
  `character_creator_page.dart` or `review_step.dart`. The spec's
  *"the same two cards sit at the bottom of the phone Greetings step"*
  (`creator-ui-spec.md:155-156`) is about the **PWA phone layout** —
  and it is already shipped that way (`ReviewSection.tsx` mounted in
  `GreetingsStep.tsx:381-387`). One UI is the tiebreak (same controls
  everywhere, only the layout adapts): the web gets the Review step on
  wide **and** phone; the phone stacks the rail above the text cards in
  a single column. Whether the two rewrite cards also stay at the
  Greetings foot on phone after Review lands is the open call (§5.2).

## 2. Build order (sections 8d-A/8d-B are commit groups in **one PR** — ruled 2026-11-15)

### 8d-A — the step itself (text, lorebook, tags, Save & Finish)

Web today: `web_ui/src/pages/CreateAiCharacterPage.tsx:48` ends at
`Realism` (`STEPS = [... 'Greetings', 'Realism']`; last button `Open in
editor`, `:445-449`). No editable text cards, no in-page lorebook edit,
no tags, no Save & Finish (the card is already saved server-side since
Profile — `chargenForm.ts:268` `pauseAtProfile: true`, host
`chargen_create.dart:207-283`).

Build:

1. **Step 8 `Review`** after Realism; the two rewrite cards move from the
   Greetings foot into the step (`ReviewSection.tsx`, 226 lines,
   already streams `chargen_rewrite_progress|done|error` over
   `GET /api/chargen/review` + `POST /api/chargen/rewrite/*`,
   `profileApi.ts:249-258`); the phone stacks the rail above the text
   cards in one column (§1; whether the phone *also* keeps the two
   cards at the Greetings foot is the open call, §5.2).
2. **Editable cards** in the desktop's order, with its `maxLines` and
   subtitles (`review_step.dart:151-237`, `_they()`/`_dialogueSubtitle()`
   at `:245-259`; per-card subtitle copy confirmed against the code —
   `review_step.dart:182, 188, 194` — and the light-wide reference
   shot, §1): Description (6),
   Personality (4), Scenario, First Message (6), each alternate greeting
   (4) with the `GreetingSeedForm` (needs + inventory) under it, Example
   dialogue card with steer/Regenerate/Stop (`:261-294`), System Prompt
   (4). Each card carries a fullscreen/expand icon button top-right
   (`creator_text_card.dart:107, 179` — `showExpandedEditorDialog`);
   the web needs a twin of that expanded editor dialog. Auto-save per keystroke-debounce as the web already
   does for `mesExample`
   (`ReviewSection.tsx:143-151`) — same verb:
   `POST /api/characters/<id>` (`character_routes.dart:78` →
   `character_card_edits.dart:29-105`).
3. **Lorebook card, full**: row list with **keep-checkboxes**, per-row
   edit dialog (the `showLorebookEntryDialog` twin), first 3 rows +
   `and {n} more` collapsed, `Edited by hand` pill via `isHandEdited`,
   steer + `Rewrite the lorebook` + Stop + caption
   (`review_lorebook_section.dart:51-61, 73, 86-101, 114, 126-133,
   137-151`). Keep semantics: Save & Finish drops unchecked entries
   (`creator_state_engine.dart:270-278`) and posts the filtered set —
   `POST /api/characters/<id>` replaces `lorebook` wholesale
   (`character_card_edits.dart:86-88`), so filter client-side and post
   once. Rewrite keeps hand-edited entries host-side
   (`creator_state_engine.review.dart:70-105`) — no new work.
4. **Tags**: read-only chip wrap of `card.tags` under the name
   (`review_step.dart:124-145`). Read-only is exact — the desktop
   creator does not edit tags.
5. **Name** centred under the portrait rail (`review_step.dart:114-122`).
6. **Save & Finish** replaces `Open in editor` on wide: it is an update
   (card exists), resets wizard state, returns Home with the created
   snackbar (`character_creator_page.dart:186-196`). Template
   "marked from" clears after it (`docs/design/creator-templates.md:82`).

Route gap for 8d: **none** for the text/lorebook/tags verbs — all ride
`POST /api/characters/<id>` (tags accepted at
`character_card_edits.dart:54-55`).

### 8d-B — portrait & expressions (the left rail)

Port `AvatarGenerationPanel` as it behaves on desktop
(`avatar_generation_panel.dart:122-156`):

1. **Portrait source tri-state** Upload my own / Generate / None for now
   (`portrait_section.dart:184-195`), Generate disabled without an
   engine with the no-engine banner + Set up (`:198-246`) — readiness
   verbs exist (`GET /api/image/studio/ready`, `/api/image/config`,
   `backend_routes.dart:76-77, 81`); this is UI work.
2. **Generate mode**: engine row (`engine_strip.dart`, 206 lines),
   `PORTRAIT PROMPT` field **seeded from the card**
   (`review_step.dart:110` → `state.buildPortraitPromptSeed()`,
   `creator_state_engine.dart:319-…`), portrait preview after a run
   (`:81-86`, `portrait_preview.dart`). Generation rides the existing
   `POST /api/image/generate` (`backend_routes.dart:78`,
   `image_facade.dart:119-165`). **Route gap**: nothing returns the
   prompt seed — extend `GET /api/chargen/review`
   (`chargen_facade.dart:242-252`) with `portraitPromptSeed`.
3. **Upload mode**: portrait upload → crop → apply
   (`portrait_section.dart:440-451`: `ImageCropDialog` →
   `controller.applyPortrait`, `avatar_creation_controller.dart:338-348`
   via `portraitWriteTarget`, `lib/services/portrait_promotion.dart:158-181`).
   Web crops browser-side with the existing `ImageCropModal.tsx` (the 8b
   precedent, `AvatarManager.tsx:64-76`). **Route gap**: no portrait
   attach/replace verb — add `POST /api/characters/<id>/portrait`
   (raw bytes) doing exactly `applyPortrait`: `portraitWriteTarget` +
   `updateCharacter` re-embedding. This also closes the Avatar Gallery
   gap named in `web-parity.md:70`.
4. **Extra upload wells** (`portrait_section.dart:329-373`) with the
   **emotion tag dialog** twin (`upload_tag_dialog.dart:26-132`: Gallery
   look vs an `EmotionLabels` value) → `addExtraUpload`
   (`avatar_creation_controller.dart:352-364`). Existing
   `POST /api/characters/<id>/avatars?label=` / `/looks` cover the
   upload itself (`character_routes.dart:62-74`); **route gap**: no verb
   to re-tag an existing avatar (`updateAvatarLabel`,
   `character_media_store.dart:210-217`) — add
   `POST /api/characters/<id>/avatars/<avatarId>/label`.
5. **Portrait veto card** Continue / Regenerate-with-edited-prompt at
   `stage == portraitReview` (`avatar_portrait_review.dart:29-180`,
   panel `:135-141`).
6. **Expressions pack**: pack switch, preset dropdown 8-base/28-all
   (`expressions_section.dart:72-81, 155-179`), Prompt rules dialog
   (`:84-94`), edit-model readiness row (`:183-245`), CTA label
   ("Generate 1 portrait · N expressions",
   `avatar_creation_controller.dart:232-242`), run progress rows and
   Cancel (`avatar_run_progress.dart:28-243`). Pack verbs all exist
   (`expression_pack_routes.dart:15-46`) with `workspace:false`, and
   `web_ui/src/components/models/studio/packApi.ts` is a complete
   client; re-run `test/hygiene/` if any of it moves while wiring
   (2026-11-15 restyle lesson).
7. **Import ZIP**: pick a zip → decode → tag-name check → per-entry
   `addAvatar` → flip `expressionEnabled`
   (`expressions_section.dart:296-334` →
   `avatar_creation_controller.dart:368-384`, decoder
   `lib/ui/dialogs/avatar_gallery/avatar_gallery_io.dart:79-111`).
   Decode in the Dart host, not the browser: add
   `POST /api/characters/<id>/expressions/import-zip` reusing
   `decodeSpritePack` + the controller loop verbatim (it already
   performs the enable flip).
8. **`ensureCardSaved` semantics** (`review_step.dart:94-109`): on the
   web the card already exists (saved at Profile), so every image verb
   targets the existing id — no anchor/double-add risk like the
   desktop's single-flight `avatar_card_anchor.dart:60-76`; keep the
   "persist before any image lands" ordering in spirit: reject image
   verbs for an unsaved card with a clear 4xx.

## 3. Ruled 2026-11-15 — Vision QC is held back

The desktop gates the Vision QC switch on capability and runs
`ExpressionPackQc` unattended, holding flagged images back
(`expressions_section.dart:95-116`; `avatar_pack_runner.dart:197-221`;
`avatar_qc_gate.dart`, `VisionSupportResolver`). The web ships **without**
the QC switch and without hold-back: packs run straight to import. Pin a
⚙️ desktop-only row in `dev-notes/web-parity.md`; no vision-probe route
is added. Everything else in §2 is parity, not optional — including the
in-page lorebook row editing (the `Open in editor` delegation that
`ReviewSection.tsx:194-223` uses today is superseded on wide; phone
keeps today's shape per §1).

## 4. Route summary (all additive)

| Verb | Purpose | Desktop twin |
| --- | --- | --- |
| `GET /api/chargen/review` + `portraitPromptSeed` field | seed the portrait prompt | `creator_state_engine.dart:319-…` |
| `POST /api/characters/<id>/portrait` | upload+crop applied as portrait | `avatar_creation_controller.dart:338-348` |
| `POST /api/characters/<id>/avatars/<avatarId>/label` | re-tag an expression | `character_media_store.dart:210-217` |
| `POST /api/characters/<id>/expressions/import-zip` | sprite-pack import + enable flip | `avatar_creation_controller.dart:368-384` |

Everything else reuses shipped routes (§2 cites each).

## 5. Decisions

1. **One PR** — ruled by the maintainer 2026-11-15. Sections 8d-A and
   8d-B land as commit groups in a single PR (#734 precedent).
2. **Phone Greetings foot**: after the web Review step ships (phone
   included, §1), does the phone *also* keep the two rewrite cards at
   the Greetings foot as the spec describes? Default ruling: no — the
   cards live only in the Review step, and the phone Greetings foot
   drops them; say otherwise and they stay.
3. **Light/dark verification**: on the dark theme, a 1440 dark shot of
   the step would help paint-check (§6 ships its own, but the desktop
   reference makes drift obvious early). Not a blocker.

## 6. Parity and test wiring

- Dart route tests under `test/services/web/` per route (bad ids 404,
  bad bodies 400, oversized 413 — the persona-import precedent from 7d).
- Vitest per new component (`*Step.test.tsx` pattern of
  `RealismStep.test.tsx`); rewrite-card reuse must not break
  `ReviewSection` tests.
- Playwright journey in `web_ui/e2e/journeys.spec.ts`: walk
  Greetings → Realism → Review, edit a card, toggle a lorebook row,
  Save & Finish; the portrait half adds the upload→crop→portrait path with a fixture
  image.
- Parity rows: `web-parity.md:63` ⏳→✅ on merge (8d-A text half, 8d-B image
  half), `:70` gains the creator portrait-upload fill, new ⚙️ row for
  Vision QC (§3).
- Screenshots: Review step + every new dialog, Porch dark and Harbor
  light, 1440 and 390, seeded data only; desktop reference shots like
  8c's.

## 7. Delivery checklist (the PR)

- `flutter analyze`; `flutter test` (`test/services/web/`,
  `test/hygiene/`); `npm run lint`, `npm test`, `npm run build`.
- 500-line cap: `CreateAiCharacterPage.tsx` is 470 — the step goes in
  `web_ui/src/components/aichargen/` as its own components, not inline;
  `wc -l` everything grown.
- Edited existing tests/goldens carry `approved-test-change`.
- `## Screenshots` and `## Hand-check` in the PR body.
