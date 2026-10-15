# AI Character Creator UI spec

The visual contract for every AI Character Creator screen, transcribed from
the approved sketch (2026-10-13). It applies to the Flutter desktop app and
the web UI identically: same sections, same labels, same controls in the same
places, same palette. Only width adaptation differs (the phone stacks what
the desktop puts side by side). A control, label or colour that is not in
this document is not in the design.

The palette is the Porch Stories one: Dart tokens in
`lib/ui/theme/studio_colors.dart` (`StudioColors`), web tokens in
`web_ui/src/styles/studio.css` (`--studio-*`), values in
`docs/design/porch-stories-ui-spec.md`. No other surface or accent may
appear in the creator: not `AppColors.cardOf`, `surfaceOf`,
`surfaceContainerOf`, `backgroundOf`, `borderOf`, `insetPanelOf`,
`textPrimary/Secondary/Tertiary`, `porchAmberOf`, nor raw `Colors.*` /
`Color(0x…)`; on the web no `var(--bg)`, `var(--surface)`, `var(--surface-2)`,
`var(--card)`, `var(--border)`, `var(--text)`, `var(--muted)`,
`var(--faint)`, `var(--porch-amber)` inside the creator pages, components or
stylesheets. The local checker enforces this on commit.

## Palette roles

| Role | Token |
|---|---|
| Page background; inset text boxes and inputs | `bg` |
| App bar (desktop), top bar (phone) | `side` |
| Cards; the Back button fill (desktop) | `card` |
| Steer fields; chips; upcoming step dots; hint box fill; menus | `raise` |
| Borders, dividers, the step lines on the phone (`line` at 60%) | `line` |
| Text | `ink` |
| Secondary text, icon buttons, hint body, text buttons | `prose` |
| Muted text (subtitles, captions, labels) | `muted` |
| Placeholders, counts, upcoming step labels | `faint` |
| Primary buttons, done and current step dots, outlined buttons, the sparkle, links | `amber`; text on an amber fill `amberInk` |
| Spoken lines inside macro-coloured boxes | `honey` |
| `{{char}}` and `{{user}}` inside macro-coloured boxes (bold on the phone) | `teal` |
| Asterisk narration inside macro-coloured boxes | `#D9C7B2` dark, `muted` light |
| Stop, Delete, destructive menu items | `bad` |
| Current step dot ring | `ink`, 2px |
| Writing card border | `amber` at 60%, 1.5px |
| Hint box border | `amber` at 50%, 1px |
| Conditional-row pill (interview) | `amber` text, `amber` at 50% border |
| Icon tiles on the mode cards | `amber` at 14% fill, `amber` icon |
| Dialog scrim | `rgba(12, 8, 4, 0.62)` |

## Type

System UI stack on both surfaces (`system-ui, -apple-system, "Segoe UI",
Roboto, sans-serif`); the creator does not use the studio's Figtree or
Literata. Sizes are given per component below. Labels above fields are 11px,
600, uppercase, 0.4px tracking, `muted`. Button labels set size and weight on
the label text, never through a `ButtonStyle.textStyle` that replaces the
theme's font.

## Desktop chrome

| Part | Spec |
|---|---|
| App bar | 56px tall, `side`, 1px `line` bottom border, 16px side padding, 14px gap. Back arrow button 40×40. Sparkle 22px amber. Title "AI Character Creator" 20px / 600. |
| Step dots | right-aligned row; each step a 52px (60px for Configure, Generate, Greetings) column: 24px circle, 3px gap, 10px label. Done: amber fill, amberInk check (13px, stroke 3). Current: amber fill, 2px `ink` ring, number 11px / 700, label `ink`. Upcoming: `raise` fill, number 11px / 600 `muted`, label `faint`. |
| Save-and-finish-later icon | 40×40, far right, 10px left margin. |
| Content column | centred; 860px wide (Profile, Greetings, Configure, Review), 960px (Mode); 32px top padding (24px on Configure); 16px gap between blocks. |
| Page title | h1 24px / 700 `ink`; intro paragraph 14px / 1.5 `muted`, 6px below. |
| Bottom nav | centred row, 14px gap, padding 18px top / 24px bottom. Back: 52px tall, 24px side padding, radius 14, 1px `line`, `card` fill, 16px / 500 `ink`, left arrow 18px. Next: 280×56, radius 16, amber fill, amberInk 16px / 500, right arrow 18px (a check for "Save & Finish"). While a rewrite runs the whole row dims to 40% and is disabled. |

## Phone chrome

| Part | Spec |
|---|---|
| Top bar | 44px, `side`, 1px `line` bottom border, 12px side padding; menu button 40×40; "Front Porch AI" 19px / 700. |
| Page head | row, 10px top / 12px side padding: "← Library" ghost button (44px tall, 8px side padding, radius 10, 14px / 500 `muted`, arrow 18px), sparkle 18px amber, "AI Character Creator" 17px / 700. |
| Step dots | row, 10px top / 16px side padding; 24px circles as on desktop (12px check), labels 10px; 2px lines between, `line` at 60%, 11px top margin, 4px side margins. Current label `prose`. |
| Content | 18px top / 16px side padding, 14px gap. h2 24px / 700; intro 14px / 1.5 `muted`. |
| Bottom bar | `bg`, 1px `line` top border, padding 12px top / 16px sides / 16px bottom, 10px gap. Back: 128px wide, 56px tall, radius 16, 1px `line`, transparent, 16px / 500. Next: flex, 56px tall, radius 16, amber, amberInk 16px / 700, right arrow 18px. |

## Components

| Component | Spec |
|---|---|
| Card | `card` fill, 1px `line`, radius 16, padding 20 (16 on the phone), 12px gap. Header row min-height 32: h3 16px / 700 `ink`, subtitle 12px `muted` 10px after, expand-to-full-screen icon button 40×40 radius 20 `prose` at the right. |
| Writing card | 1.5px border, amber at 60%; header shows "Writing…" 12px / 600 amber in place of the subtitle; streamed text with a 2×16 amber caret; the expand button at 35%. |
| Macro-coloured text box | `bg` fill, 1px `line`, radius 12, padding 12×14, 15px / 1.55 `ink`; macro, spoken and narration colouring as above; min-height 96. On the phone the box is capped at 132px (108 for Scenario) and scrolls. |
| Steer field | `raise` fill, no border, radius 12, 14px `ink`, placeholder `faint`. Single line: 44px tall, 14px side padding. Growing (the profile): a textarea, min-height 44, padding 12×14, line height 1.4, grows with its text, no resize handle. |
| Outlined action button | 44px tall, 18px side padding, radius 12, 1.5px amber, amber text 14px / 700, 18px icon, 8px gap. Phone full-width variant: 48px tall, 16px / 700. Stop: the same shape in `bad`. |
| Small outlined button | 36px tall, 12px side padding, radius 10, 1.5px amber, amber 13px / 700, 16px icon (Re-read from the profile). Phone: full width, 44px tall, 14px / 700. |
| Text button | 36px tall, 12px side padding, radius 10, transparent, amber 13px / 600 (Open the lorebook editor, Reset to the standard questions). In a hint box: `prose` 14px / 500 (Keep them). |
| Caption | 12px / 1.5 `muted`, under the control it explains. |
| Field | label (11px rules above), input 40px tall (44 on the phone), `bg` fill, 1px `line`, radius 10, 12px side padding, 14px `ink`. Text areas: padding 10×12, line height 1.45. |
| Chip | 34px tall (36 on the phone), 10px side padding, radius 10, `raise` fill, 13px `ink`, 6px gap, remove × 14px `muted`. "+ add": the same height, 1px amber border, transparent, amber 13px / 700. |
| Facts grid (desktop) | row one: three columns (Birthday, Occupation, Hours · work days); row two: two columns (Opening task, Opening stance, Ambitions, Warms to, Put off by, Intimate preferences); then Creator notes full width; 12px row gap, 20px column gap. Phone: every field stacked, 6px label gap. |
| Collapsed row | 44px tall button, 14px side padding, radius 12, 1px `line`, transparent, chevron 18px, title 14px / 500 `prose`, note 12px `muted`. |
| Hint box | `raise` fill, 1px amber at 50%, radius 12, padding 16×18, 12px gap; info icon 22px amber; title 15px / 700 `ink`; body 14px / 1.5 `prose`; buttons row 18px gap: outlined 40px tall 16px padding radius 10 amber 14px / 700, then a `prose` text button. |
| Lorebook entry row | `bg` fill, 1px `line`, radius 12, padding 10×14, 12px gap; name 14px / 600 `ink` at 180px; preview 13px `muted` one line, ellipsis; "Edited by hand" pill 11px / 600 `muted`, 1px `line`, radius 8. Rows beyond three: "and {n} more" 12px `faint`. |
| Mode card | `card`, 1px `line`, radius 16, padding 20, 12px gap; icon tile 52px radius 14 amber-at-14% fill with a 28px amber icon; title 18px / 700; subtitle 13px `prose`; description 12px / 1.5 `muted`; feature list 11px `muted`. Phone: a row card, 44px icon tile, title 16px / 700, subtitle 12px. |
| Dialog | `card`, 1px `line`, radius 20, padding 24, 16px gap, 520px wide; title 20px / 700 with a 22px amber icon; body 14px / 1.5 `prose`; Cancel `prose` text button 44px, confirm amber 44px radius 12 14px / 700. Phone: a bottom sheet, radius 20 on top, 40×4 handle, stacked buttons (confirm 52px, Cancel 44px). |
| Menu | `side` fill, 1px `line`, radius 10, 6px padding, items 36px tall 10px padding radius 8 14px; destructive in `bad`. |
| Template picker card (Mode step) | Desktop: a card (padding 18×20×20, 14px gap) above the mode cards; header row 10px gap: bookmark icon 20px amber, title `Start from a template` 16px / 700, subtitle 12px `muted`. Tiles 176px wide in a 12px-gap row that wraps: `bg` fill, 1px `line`, radius 12, padding 12×12×10, 6px gap; name 14px / 600 `ink` (a button), summary 12px / 1.4 `muted`, `Saved {d Mon}` 11px `faint`; a ⋯ button 28×28 radius 14 at the top right (menu: Load, Rename, Delete in `bad`); a built-in tile carries the `Built in` pill (11px / 600 amber, 1px amber at 50%, radius 8, padding 1×7) and no menu; the selected tile has a 1.5px amber border; the last tile is dashed (`lineStrong`), `All 15 built in ›` 14px / 600 amber with a 12px `muted` line under it. Phone: h3 row (icon 18px, `Start from a template` 15px / 700) then a horizontal scroll of 168px tiles (`card` fill, padding 12) and a 120px dashed tile. |
| Configure header (desktop) | Title and intro as today; when started from a template, under the intro: a pill 28px tall, 10px side padding, radius 14, amber at 12% fill, amber 12px / 600 with a 14px bookmark, `Started from: {name}`, then the caption `Changes stay on this form until you save them to the template.` 12px `faint`; at the header's right the outlined action button `Save as template` (44px, 16px padding, radius 12, 1.5px amber, amber 14px / 700, 18px bookmark). Phone: the pill and caption above a full-width outlined `Save as template` at the bottom of the Output step. |
| Save-as-template dialog | The Dialog component: bookmark icon 22px amber + `Save as a template` 20px / 700; body 14px / 1.5 `prose`; field label `TEMPLATE NAME`, a steer-style field (`raise` fill, no border, radius 12, 44px, 14px side padding) prefilled with the started-from name; under it either the name problem in `bad` or the replace caption in amber; `Cancel` (`prose` text button 44px) and `Save template` (amber 44px radius 12 14px / 700, disabled on a problem). Phone: the bottom sheet (radius 20 top, 40×4 handle, stacked buttons, confirm 52px). Rename uses the same field; Delete confirms with the warm dialog's destructive form. |
| Interview card | A card (padding 20 desktop / 16 phone, 14px gap / 12px). Header: title 16px / 700; intro 12px / 1.5 `muted`; pill row: pill 26px tall, 10px side padding, radius 13, amber at 12% fill, amber 12px / 600, then (desktop) a 12px `faint` caption; at the right the text button `Reset to the standard questions` (phone: `Reset`, 32px tall, 8px padding). Rows 8px apart, each a row with 10px gap (8 on the phone): handle 24×44 `faint`, six dots (1.6px radius), grab cursor; number 22×44 (20 on the phone) 13px / 600 `muted`; text area flex, `bg` fill, 1px `line`, radius 12, padding 10×14 (10×12 phone), 14px / 1.45 `ink` (16px phone), grows with its text, no resize handle; remove button 40×44 transparent `muted` × 18px. Conditional row: 1px dashed `#4E4134` border, text `#E8DDCF`, a pill under it 11px / 600 amber, 1px amber at 50%, radius 8, padding 1×7, and a 40px spacer in place of the remove button. Edited row: 1.5px amber border and a pill 11px / 600 `muted`, 1px `line`, radius 8. Footer: `Add a question` 40px tall, 14px side padding, radius 10, 1px dashed amber, transparent, amber 14px / 700 with a 16px plus (phone: full width, 44px tall, radius 12); count caption 12px `muted` (centred on the phone). |

## Screens, sections and labels

These lists are compared between Dart and web by the local checker.

Desktop steps, in order: `Setup`, `Mode`, `Configure`, `Generate`, `Profile`,
`Greetings`, `Realism`, `Review`. Phone steps: `Mode`, `Details`, `Output`,
`Generate`, `Profile`, `Greetings`; the last button is `Open in editor`.

**Profile step.** Title `Profile`. Desktop intro: `This is who the interview
wrote. Read it before anything else is built: the greetings, lore, outfit and
picture prompt are written after you press Next. Edit any box by hand, or
tell the rewrite what is wrong.` Phone intro: `Who the interview wrote.
Greetings and the rest are written after Next. Edit a box, or tell the
rewrite what is wrong.`

Cards, in order, each with its subtitle (desktop only): `Description` /
`Who they are, as the card will carry it`; `Personality` / `How they act and
speak`; `Scenario` / `Where the first chat starts`. While writing: the
Description subtitle reads `Writing…`, Personality `Waiting for the
description…` then `Writing…`, Scenario `Kept as it is`.

Rewrite card: steer placeholder `What is wrong or missing? e.g. Does not
follow the Tsundere personality type`; button `Rewrite the profile`; while
writing the button is `Stop`. Caption (desktop): `Rewrites Description and
Personality from the interview and your direction, then re-reads the facts
below from the new profile. The box grows as you type. A scenario you typed
yourself is kept.` Phone caption drops the "box grows" sentence. While
writing: `Writing a new Description, then a new Personality, then re-reading
the facts below. Stop keeps the old text everywhere.`

Facts card: title `Also written from the interview`; subtitle `Every Front
Porch field is filled whether or not you use it. Mood, time of day and
outfit follow once the greeting exists.` (phone: `… follow the greeting.`);
button `Re-read from the profile`; while a rewrite runs the card dims to 45%
and the subtitle reads `Re-read after the rewrite` in amber. Labels, in
order: `BIRTHDAY · AGE {n} FROM SETUP` (phone `BIRTHDAY · AGE {n}`),
`OCCUPATION`, `HOURS · WORK DAYS`, `OPENING TASK`, `OPENING STANCE TOWARD
{{user}}`, `AMBITIONS`, `WARMS TO`, `PUT OFF BY`, `INTIMATE PREFERENCES ·
18+ IS ON` (the row is absent when 18+ is off; sub-labels `into` and `not
into`), `CREATOR NOTES · THE PITCH`. Chip lists end with `+ add`.

Collapsed row: `Interview transcript` / `{n} questions, read only, so you can
see where the rewrite came from`.

Bottom nav: `Back`, `Next: Greetings`.

**Greetings step hint** (above the first message card when the profile was
rewritten after the greetings were written): title `The profile changed`;
body `These greetings were written from the old Description and Personality.
Nothing was changed for you.`; buttons `Rewrite the greetings from it`,
`Keep them`.

**Review step** (desktop; the same two cards sit at the bottom of the phone
Greetings step). Title `Review`; intro `Everything the creator wrote, in one
place. The profile and greetings are above. Example dialogue and the
lorebook take the same line of direction as the rest.`

Example dialogue card: `Example dialogue` / `How {they} answer, learned from
the interview` (pronoun from the Sex field; "they" when unknown); steer
placeholder `Steer it (optional), e.g. shorter lines, more bite`; button
`Regenerate`.

Lorebook card: `Lorebook` / `{n} entries`; text button `Open the lorebook
editor`; up to three entry rows then `and {n} more`; hand-edited rows carry
`Edited by hand`; steer placeholder `Steer it (optional), e.g. more about the
town, less about the sea`; button `Rewrite the lorebook`; caption `Rewrites
the entries from the profile and your direction. An entry you edited by hand
is kept.` Last button `Save & Finish`.

**Mode step** (desktop): title `How do you want to create?`; intro `Choose
the creation mode that fits your workflow.`; the three mode cards keep their
current copy. (The template picker above them is PR 3.)

**Mode step, templates.** Card title `Start from a template`; desktop
subtitle `Every box filled the way you saved it. Pick one, or choose a mode
below to start blank.`; phone intro `Pick a template, or a mode to start
blank.` (the phone keeps its Name field and its mature-content switch above
the picker). Tiles: your templates newest first (`{Mode} · {1st|3rd}
person, {present|past} · lore on · 18+`, the parts that apply; `Saved {d
Mon}`, with the year when it is not this year), then `Tsundere` and
`Kuudere` with the `Built in` pill and a blurb from the archetype's
keywords (two on the desktop, one on the phone), then `All 15 built in`
with `Yandere, Femme Fatale, Dark Lord and the rest`, which opens the
`Built-in templates` picker. Menu items `Load`, `Rename`, `Delete`; a file
that cannot be read shows `This file can't be read` and only Delete.

**Configure header** (desktop, every mode) and the phone's Output step:
`Started from: {name}`, `Changes stay on this form until you save them to
the template.`, button `Save as template`.

**Save as a template.** Title `Save as a template`. Desktop body `Keeps
every box on this form the way it is now: the mode, your vision and the
interview boxes, output settings, lore, 18+ and the rest. Not the
character's name.` Phone body `Keeps every box on this form the way it is
now, in every step. Not the character's name. It shows on the desktop
too.` Field `TEMPLATE NAME`. Captions: `A template with this name already
exists. Saving replaces it.`; problems `Give the template a name.`, `Keep
the name to 80 characters or fewer.`, `{Name} is a built-in template and
can't be changed. Give yours another name.`; on rename `Another template
already has this name.` Buttons `Cancel`, `Save template`. Delete asks
`Delete this template?` with `Delete` in `bad`.

**Interview card** (every mode; directly after the card that holds the
Narrative voice selector: the Output settings card on the desktop Configure
step, the end of the phone's Output step). Title `Interview`. Desktop intro:
`The character is interviewed before the profile is written. Every answer
reaches every later step. Edit any question, drag to reorder, or add your
own. Each one is a model call, so fewer is faster on a local model. Voice
first and appearance last works best.` Phone intro: `Asked before the
profile is written. Each question is a model call. Voice first, appearance
last works best.` Pill: `Answered in {first|third} person, {present|past}`;
desktop caption beside it: `Follows Narrative voice above.` in the first
person, `Follows Narrative voice above. {Her} own words are quoted when
{she} speaks.` in the third (pronouns from the Sex field; `Their … they`
when unknown). Text button `Reset to the standard questions` (phone
`Reset`). Conditional pills: `Asked only when a relationship is set`, `Asked
only when 18+ is on`. Edited pill: `Edited · kept as written`. Footer
button `Add a question`; caption desktop `{n} of 12 · remove them all and
the profile comes straight from your settings, no interview`, phone `{n} of
12 · none means no interview`. The eleven standard questions and their
first-person twins live in `lib/services/chargen/interview_questions.dart`
and are the copy on both surfaces.

## Parts the sketch does not draw (settled during the build, both surfaces)

- Selected chips: amber fill, amberInk text. Selected mode card: 2px amber
  border, amber at 8% fill.
- The Generate step's button: amber, 48px tall, radius 12.
- "Add another greeting": dashed 1.5px amber outline, amber 14px / 700.
- Section sub-headings inside a step: 16px / 700 with a 1px `line` rule
  above.
- Upcoming step-dot numbers are `muted` (the spec), on both surfaces.
- Phone macro boxes colour `{{char}}` / `{{user}}` only (teal, bold), as
  drawn; the desktop boxes also colour spoken lines (honey) and narration.
- Phone text inputs and text areas render at 16px so iOS Safari does not
  zoom on focus; the spec's 14px applies to desktop fields and to non-input
  text on the phone.
- The web's shared wizard base rules (`styles/wizard.css`, used by the
  Group, World-from-Wiki and manual Create wizards) keep the app tokens; the
  creator restyles them under its own scope and bridges the old token names
  to the studio ones there, so shared pieces rendered inside the creator
  (global buttons and inputs, the macro field, notes) take the palette too.
- The birthday field shows and edits the stored date (`YYYY-MM-DD`); the
  label carries the age it must match. The sketch's "14 March" was a
  stand-in for that value.
- The Interview card: the sketch's dimmed "Narrative voice" row above it
  stands for the existing selector, so the card follows the card that holds
  that selector (the Output settings card on the desktop Configure step; the
  end of the phone's Output step, which the phone's "Details" board stood
  in for). The phone rows carry the same six-dot handle as the desktop and
  drag by pointer, since reorder must exist on both surfaces.
- Templates: the app ships fifteen archetypes, not the sketch's fourteen,
  so the tile reads `All 15 built in` and a test pins the count to the
  label. The sketch's "2nd person" summary does not exist; summaries say
  1st or 3rd person. Built-in blurbs come from the archetype's keywords.
  The desktop tile row wraps when there are more templates than fit; the
  phone scrolls sideways. The phone keeps its Name field and mature switch
  on the Mode step and shows the `Started from` pill and caption above its
  Save button on the Output step, which the phone board does not draw. The
  shared warm dialog reads the creator palette when opened inside the
  creator, so Save, Rename, Delete and the built-ins picker match the
  Dialog row without a second dialog primitive.
- The web app is dark-only today (nothing sets a light theme); the studio
  light tokens are in place for when it gains one. The app shell around the
  creator (side rail, drawer, top bar outside the creator) keeps the app
  palette; only the creator's own top bar goes warm while it is open.

## States the sketch fixes

- The Generate screen shows twice: once for Phase A (ends on Profile), once
  for Phase B after Next on Profile (ends on Greetings). Same spinner,
  status line, progress bar and Abort.
- While the profile rewrite runs: Description and Personality are writing
  cards; Scenario stays; the rewrite button is Stop; the facts card dims and
  reads "Re-read after the rewrite"; the transcript row is disabled at 50%;
  Back and Next are disabled at 40%.
- The facts card's Re-read dims the card the same way while it runs.
- The Greetings hint shows only when the profile text differs from the text
  the greetings were written from; "Keep them" records the current profile
  as that text.
- The Review rewrites lock their own card while writing, with Stop; the
  other card and the nav stay live.
- The Interview card's count caption switches to `{n} of 12 · no
  interview: the profile comes straight from your settings` (phone `… comes
  from your settings`) once no unconditional row with text is left, since the
  two conditional rows cannot be removed. On the phone the rows and Add lock
  while the standard set for a new voice or Sex is being fetched.
