# Porch Stories UI spec

The visual contract for every Porch Stories screen, transcribed from the
approved mockups (sketch sets A–G and H–W). It applies to the Flutter desktop
app and the web UI identically: same sections, same labels, same controls in
the same places, same palette. Only width adaptation differs (the sidebar
becomes a strip under 760px).

The Dart tokens live in `lib/ui/theme/studio_colors.dart` (`StudioColors`), the web
tokens in `web_ui/src/styles/studio.css` (`--studio-*`). The values in the
table below are the source; the other two must match it exactly.

## Palette

| Token | Dark | Light | Dart | CSS |
|---|---|---|---|---|
| Page background | `#1B1611` | `#F8F4ED` | `StudioColors.bg` | `--studio-bg` |
| Sidebar / header surface | `#1F1913` | `#F0EBE3` | `StudioColors.side` | `--studio-side` |
| Card | `#251E17` | `#FFFDF9` | `StudioColors.card` | `--studio-card` |
| Raised (selected nav, secondary button, inset) | `#30271E` | `#E9E2D8` | `StudioColors.raise` | `--studio-raise` |
| Hairline | `#3E3328` | `#D4CFC6` | `StudioColors.line` | `--studio-line` |
| Text | `#EFE6DA` | `#2A231C` | `StudioColors.ink` | `--studio-ink` |
| Muted text | `#A89A89` | `#6E6357` | `StudioColors.muted` | `--studio-muted` |
| Faint text (placeholders, counts) | `#7A6E62` | `#9A8E82` | `StudioColors.faint` | `--studio-faint` |
| Prose | `#E8DDCF` | `#2A231C` | `StudioColors.prose` | `--studio-prose` |
| Amber (primary action, selection) | `#F4A259` | `#B45309` | `StudioColors.amber` | `--studio-amber` |
| Honey (sequence headings, planning chips, "new") | `#E9C46A` | `#8F6400` | `StudioColors.honey` | `--studio-honey` |
| Terracotta (tension bars, prose chips) | `#E29578` | `#9C4B2F` | `StudioColors.terra` | `--studio-terra` |
| Teal (written, pass, good) | `#4DB6AC` | `#00695C` | `StudioColors.teal` | `--studio-teal` |
| Bad (fail, banned, destructive) | `#E57373` | `#B3261E` | `StudioColors.bad` | `--studio-bad` |
| Ink on amber (text on a primary button) | `#2A1A08` | `#FFFDF9` | `StudioColors.amberInk` | `--studio-amber-ink` |

Portrait placeholder gradient `#6A4A2A` → `#30271E` with honey initials; shelf cover gradient `#4A3421` → `#251E17`. Chip borders are the accent at ~45% alpha; continuity diff: deleted text on
`#3A1E1C` with `#F0B3AE`, inserted on `#16302D` with `#A6E3DB`.

No other surface or accent may appear in story UI: not `cardOf`, `surfaceOf`,
`surfaceContainerOf`, `backgroundOf`, `borderOf`, `textPrimary/Secondary/
Tertiary`, `frostAccentOf`, `fixationAccentOf`, `bondHighOf`, `journalAccentOf`,
`taskAccentOf`, `emotionAccentOf`, nor raw `Colors.*` / `Color(0x…)`. On the
web, no `var(--surface)`, `var(--card)`, `var(--border)`, `var(--text)`,
`var(--muted)` inside the story stylesheet or story pages.

## Type

| Role | Family | Fallback | Use |
|---|---|---|---|
| UI | Figtree | system sans | everything that is not prose or a number |
| Prose | Literata | Georgia, serif | beat text, interview quotes, the reader, bible fields |
| Mono | JetBrains Mono | Menlo, Consolas | scene labels ("3.3"), "from 3.3", times, token counts, run-log rows |

Sizes: UI 13.5px body, 11px uppercase labels with 0.08em tracking, prose
14.5px / 1.7 line height, reader prose 17px / 1.75, mono 12px.

## Components

| Component | Spec |
|---|---|
| Card (`wc`) | card fill, 1px hairline, radius 10, padding 12×14, gap 8. Selected: amber border + 1px amber ring. Raised variant uses the raised fill. |
| Primary button | amber fill, ink-on-amber text, 600 weight, radius 8, padding 6×12. |
| Secondary button | raised fill, hairline, text colour. Ghost: transparent. Danger: bad text, bad border at 45%. |
| Chip | pill, 11.5px, 1px hairline, muted text, 2×9 padding. Accent chips (amber / honey / teal / bad / terra) colour the text and border. Pick chips: raised fill; selected = amber fill + ink text. |
| Segmented | hairline frame, radius 8, selected segment amber fill + ink text. |
| Toggle | 34×19, line fill; on = amber fill with ink knob. |
| Radio | 16px ring, line colour; on = amber. |
| Field | page-background fill, hairline, radius 8, 7×10 padding. Picker fields end with ▾. |
| Sidebar | 190px, side surface, group headings 10.5px uppercase muted; item 6×10 radius 7; selected = raised fill, text colour, 3px amber inset on the left; counts in mono faint on the right; "new" badge honey outline. Under 760px: horizontal strip, selected item underlined 3px amber. |
| Header | side surface, 10×16 padding, title 700, subtitle 12.5 muted; a 4px progress bar under it (amber; teal when finished). |
| Scene row | grid 44 / 22 / 1fr / auto; mono number, lens glyph in a 22px raised square, title + "cast · place · value → value" muted; tension bars 4px wide, terracotta filled; type chip; status chip (teal Written, amber in progress, plain Not planned); ⋯ menu. |
| Menu | raised fill, hairline, radius 8, 4px padding, items 6×10; destructive items in bad. |
| Dialog | card fill, radius 12, padding 16, title 15/700, body muted small; Cancel ghost + confirm primary (or danger). Always says what will be lost. |
| Step dots | 20px circles, mono digit; done = honey fill, current = amber fill; labels 10.5px. |
| Progress bar | 4px, line track, amber fill. |
| Shelf card | cover 84px (dark gradient, serif title, engine chip top-right), title 14/600, genre line muted, progress bar, "where you are · when". |

## Screens, sections and labels

These lists are compared between Dart and web by the local checker.

Studio sidebar, in order: `Overview`, `Structure`, `Write`, `Read`, `Director`
(group "Story"); `Cast`, `Relationships`, `Lore & continuity` (group "World");
`Run log` (group "Engine").

New Story steps, in order: `Idea`, `Cast`, `Shape`, `Engine`. Footer buttons:
`Cancel` / `Back`, `Next: <step>`, last step `Build the story bible`.

Model picker options, in order: `Same as chat`, `Worker model` (only when a
worker is set up), `Another host`; hosts: `KoboldCpp`, `OpenRouter`,
`Nano-GPT`, `xAI`, `LM Studio`, `oMLX`, `Custom`.

Studio header: `← Stories`, title, `Act <n> · <written> / <target> words`,
run status chip + `Stop` while running, `Setup`, `⋯` (Export eBook, Export
audiobook, Export text, Rename, Delete story…).

Structure toolbar: `Continue writing` (primary), `Autopilot…`.
Scene ⋯ menu: Write this scene, Plan beats, Change lens…, Edit title &
summary…, Insert scene after…, Rewrite prose…, Delete scene….
Write bottom bar: `Rewrite beat <n> with a note…`, `Change lens`, `Write next
beat`. Beat ⋯: Edit text by hand, Rewrite, Rewrite with a note…, Copy.
Read bar: `Book | Scroll`, `Read aloud`, `Contents`, `⋯`.
Lore segmented: `Continuity | Lore | Story so far`; buttons `+ Add fact`,
`Add lore file`, `Test search`.

## Behaviour the mocks fix

- One Stop (header). No running overlay; the active section streams in place.
- Autopilot writes remaining scenes only; it never regenerates the bible.
- Every destructive action confirms with a warm dialog naming what is lost.
- Setup is editable after the fact (`Setup` in the header).
- New Story creates the project on the first `Next`, not before.
- Export has one implementation, reached from the header ⋯ and the reader.
- One voice picker, on the cast card.
- Read is a section; the sidebar collapses behind ☰ while reading.
