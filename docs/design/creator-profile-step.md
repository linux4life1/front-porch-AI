# The AI Character Creator writes the whole card, and you read it before anything else is built

**Date:** 2026-10-13
**Status:** Approved design (sketch approved by the maintainer 2026-10-13); PR 1 of 3
**Branch:** feat/creator-profile-step → Rawhide
**Issue:** #530 (review the description before the greetings step)
**Audience:** an implementing agent (the maintainer cannot read Dart)

---

## Overview

Today the AI Character Creator writes the profile, the greetings, the example
dialogue, the lorebook and the Porch Life lists in one pass, and the user first
sees the description on the last step. If the model dropped half of what they
asked for, they find out after they have polished every greeting (#530).

This PR makes four changes to the creator, on the desktop and the phone:

1. **A Profile step** between Generate and Greetings. Generation pauses after
   the profile is written. The user reads Description, Personality and
   Scenario, edits any box, or steers a rewrite with one line ("Does not
   follow the Tsundere personality type"). Nothing downstream is written until
   they press Next.
2. **Every Front Porch field is written**, whether or not the user runs the
   feature it belongs to: birthday, occupation, hours, opening task, opening
   stance, ambitions, plan lines, likes, dislikes, intimate preferences (18+),
   creator notes, and after the greeting, mood, time of day, outfit and
   pockets. They are shown on the Profile step as an "Also written" card and
   can be re-read from the profile at any time.
3. **Every generated thing can be steered and rewritten**: the profile, the
   facts card, each greeting (already shipped), the outfit (already shipped),
   the example dialogue and the lorebook. Rewriting the profile after
   greetings exist raises a hint on the Greetings step.
4. **The creator moves to the Porch Stories palette** (the warm brown base),
   every step, both surfaces. The approved sketch is the pixel spec.

Two further PRs follow this one and are out of scope here: editable,
voice-aware interview questions, and creator templates.

---

## Decisions (settled by the approved sketch; do not re-open)

### The pause

`CharacterGenerator.run()` becomes two phases with one resumable state:

- **Phase A, the profile:** base card (with the JSON retry and the
  truncated-field recovery), the interview, the interview rewrite of
  description / personality / scenario, then the **identity facts pass**
  (below). Ends by handing the card, the interview transcript and the run
  inputs back to the creator state (desktop) or the relay (phone).
- **Phase B, the rest:** example dialogue, lorebook, greeting recipe stamp,
  first message, alternate scenarios and greetings, the greeting-time Porch
  Life pass, the image prompt, the narrative-voice stamp. Runs when the user
  presses Next on the Profile step; the Generate screen shows again with its
  status, progress and Abort, then lands on Greetings.

Abort and the stale-epoch guard work as today in both phases. A user who
goes Back from Profile to Configure and generates again starts Phase A over.

### Rewrite the profile

Reruns only the interview rewrite with the **same** transcript plus a
"DIRECTION FROM THE AUTHOR" block, the same shape the greeting steer uses.
The interview is not repeated. A scenario the user typed stays verbatim (the
existing `preserveUserScenario` rule). While writing: the Description and
Personality cards take the amber "writing" border, the header reads
"Writing…", text streams in, Stop keeps the old text, Back and Next dim to
45% and wait (the Greetings step's lock). After the rewrite the facts card is
re-read from the new profile.

### The identity facts pass (profile-time)

One structured call, tools first then the JSON text floor (the Porch Life
transport), reading the whole transcript and the three profile fields.
Writes onto `FrontPorchExtensions`:

| Field | Rule |
|---|---|
| `birthday` | consistent with the form's Age field; month and day the model's choice |
| `occupation`, `occupationBrief`, `hours`, `workDays` | from how the character lives; the Porch Life job system reads these and must never invent a job |
| `currentTask` | the opening task, in the character's voice |
| `shortTermBond`, `trustLevel` | from the relationship: strangers 0 / 0; warm +10..+20; guarded 0; cold or betrayed negative |
| `ambitions`, `planLines` | long-term wants across the whole story |
| `likes`, `dislikes` | small specific things they warm to / that make them bristle |
| `intimateInto`, `intimateNotInto` | only when 18+ is on |
| `creatorNotes` | a two or three sentence pitch; no personal names |

Chaos, needs baselines, the verification knobs, system prompt and
post-history instructions stay user-only: they are settings and instructions,
not facts about the character.

### The greeting-time pass

The existing Porch Life pass keeps `worn` / `carrying` (the outfit must match
the opening beat) and additionally writes `characterEmotion` +
`emotionIntensity` (the mood at the opening beat) and `timeOfDay` +
`storyStartTime` (from the scenario and the greeting). The Realism step shows
those as seeded values instead of defaults; its controls are unchanged.

### Every reader gets the whole interview

Today the greeting prompt reads the first 1,000 characters of the transcript,
the lorebook pass the first 1,200, Porch Life the first 1,400. One answer is
about 900 characters plus its question, so those readers only ever saw the
voice answer. Every reader now gets the full transcript, bounded by one shared
cap constant (12,000 characters) defined in one place. This also makes the
question order stop deciding what the lists are seeded from, which matters
once questions become editable (PR 2).

### Rewrite everywhere

| Thing | Control | Keeps |
|---|---|---|
| Profile | steer + Rewrite the profile | a user-typed scenario; the facts are re-read after |
| Facts card | Re-read from the profile | nothing; the pass is cheap |
| Each greeting | steer + Regenerate (shipped) | the other greetings |
| Outfit | Re-read the outfit from it (shipped) | |
| Example dialogue | steer + Regenerate (Review on desktop; the phone Greetings step) | |
| Lorebook | steer + Rewrite the lorebook (same places) | entries edited by hand |

Hand-edited lorebook entries are recognised by comparing each entry with the
text the generator wrote (kept alongside the card in creator state, not in
the database); an entry that differs is kept as written and marked "Edited by
hand" in the list.

### The profile-changed hint

If the user reaches Greetings, goes Back, and rewrites the profile, the
Greetings step shows the same hint box the Realism step uses for the outfit:
"The profile changed" / "These greetings were written from the old
Description and Personality. Nothing was changed for you." with **Rewrite
the greetings from it** (regenerates every greeting through the shipped
regenerate path) and **Keep them**. "Changed" is derived by comparing the
profile text with the text the greetings were written from, never from the
one action that triggered it (lesson from the outfit hint).

### Palette

The creator uses the Porch Stories studio palette on every step, desktop and
phone. Desktop: `StudioColors` in `lib/ui/theme/studio_colors.dart`. Web:
`--studio-*` in `web_ui/src/styles/studio.css`. The three agree value for
value. Mapping from the sketch:

| Role | Token |
|---|---|
| page background, inset text boxes | `bg` |
| app bar, phone header | `side` |
| cards, Back button | `card` |
| steer fields, chips, upcoming step dots, hint box fill | `raise` |
| borders, dividers | `line` |
| text | `ink`; secondary `prose`; muted `muted`; placeholders and counts `faint` |
| primary button, done and current step dots, outlined buttons, links | `amber` with `amberInk` text |
| spoken lines in the macro-coloured boxes | `honey` |
| `{{char}}` / `{{user}}` | `teal` |
| asterisk narration | a muted warm (`#D9C7B2` dark, `muted` light) |
| Stop, Delete | `bad` |
| hint box border | `amber` at 50% |

No slate, no blue, no `AppColors.cardOf` / `surfaceOf` in the creator after
this PR. The raw-colour ratchet must not gain a file.

---

## Surfaces

### Desktop

Setup → Mode → Configure → Generate → **Profile** → Greetings → Realism →
Review. The Profile step: title, intro line, three profile cards, the rewrite
card (growing steer box + Rewrite the profile + caption), the "Also written
from the interview" facts card (three-column facts row, two-column task /
stance row, chip lists for ambitions, warms to, put off by, intimate 18+,
then creator notes; "Re-read from the profile" in its header), a collapsed
"Interview transcript" row, Back / Next: Greetings. Review gains the two
rewrite rows.

### Phone (web_ui)

Mode → Details → Output → Generate → **Profile** → Greetings → Open in
editor. The same Profile content stacked; the facts card's Re-read is a full
width button; the example dialogue and lorebook rewrite cards sit at the
bottom of the Greetings step, which is the phone's last step. The phone talks
to the relay only.

### Relay (`/api/chargen/*`, additive)

Create becomes two phases. The first returns the profile and holds the
pending generation; a continue route runs Phase B. Routes for profile
rewrite, stop, status, facts re-read, example-dialogue regenerate and
lorebook rewrite follow the greeting routes' shape. Progress streams over the
existing WebSocket hub. The pending generation lives on the record the phone
will look at after a reload, with memory as a cache (lesson from the greeting
recipe).

---

## Tests (proven red first)

- Desktop: the real wizard with the scripted-model generator the creator
  tests use. Every mode lands on Profile after Phase A with nothing
  downstream written; Next runs Phase B and lands on Greetings; steer and
  Rewrite; the lock while writing; Stop keeps the old text; Re-read; the
  facts card seeded; the Greetings hint after a rewrite and after a hand edit;
  Review rewrites; a hand-edited lorebook entry survives a rewrite. Appended
  to the existing creator test files.
- Engine: the identity pass writes every field listed above; every reader
  receives the whole transcript (a transcript longer than 1,400 characters
  whose later answers must appear in the prompt each reader sends).
- Relay: the real router, the real hub over a real WebSocket, a real
  repository and database; two-phase create survives a relay restart.
- Web: component tests for the new step and cards; a journey in
  `web_ui/e2e/journeys.spec.ts`; the route in `sweep.spec.ts`.
- Goldens (Linux-gated): the Profile step, the writing state, the facts card,
  light and dark.
- Live: the creator run end to end on the Linux media server, desktop and
  phone, with screenshots beside the sketch in the PR body.

---

## Implementation shape (reconciled 2026-10-13)

- **Engine seam.** `CharacterGenService` keeps `generateCharacter` (both
  phases back to back, byte-for-byte today's behaviour for Scene Guest and
  the one-shot relay create) and gains `generateProfile` → `GenPausedRun`
  (inputs, card, full transcript, facts), `completeCharacter(paused)`,
  `rewriteProfile`, `rereadIdentityFacts`, `regenerateExampleDialogue`,
  `rewriteLorebook`. The paused run is plain data with no epoch; every later
  action runs on a fresh service instance with its own `beginRun`, the way
  the greeting writer does. Phase B works on a copy of the paused card, so an
  abort during Phase B returns to the Profile step with the pause intact.
- **Inputs.** The 27 generation parameters become one `GenRunInputs` value,
  which also carries the automated mode's description override so both
  surfaces show it on the Profile step from one place.
- **Transcript cap.** One constant, 12,000 characters, applied by every
  reader including the greeting-recipe stamp (a fourth reader the first
  survey missed).
- **Identity facts** are a pure value (`IdentityFacts`, JSON for the relay)
  parsed from a tool call or loose JSON; the model emits month and day, Dart
  composes a birthday consistent with Age; the model emits a warmth word
  (strangers / warm / guarded / cold) and Dart maps bond and trust; a blank or
  stranger relationship forces strangers. The Porch Life pass merges instead
  of overwriting, so an empty list never wipes what the facts pass wrote.
- **Streaming the rewrite.** The rewrite returns one JSON with three fields.
  A small pure parser reads the partial stream and shows the description's
  text inside the Description box while it arrives, then switches the
  Personality card to "Writing…" when its key appears, as the sketch draws
  it. The same parser serves the phone.
- **Hand-edited lorebook entries** carry a fingerprint of their generated
  text in the entry's free `extensions` map (already round-trips DB and PNG);
  an entry whose text no longer matches is hand-edited and kept. If a path
  drops the map, everything counts as hand-edited: nothing is lost.
- **Profile changed** is a fingerprint of description and personality
  stamped on the greeting recipe when greetings are written; "Keep them"
  re-stamps. Desktop and relay read the same stamp.
- **Relay pending run** is written to a file in app support when Phase A
  ends and read back at start, so a phone reload after a relay restart still
  finds it. A second create replaces the pending run; nothing was saved.
  Desktop holds its pause in creator state.
- **Opening stance** on the facts card is shown as a field but read only
  (strangers · bond · trust); bond and trust are edited on the Realism step.
- **Retheme scope** is every file under `lib/ui/character_creator/`
  (World from Wiki included), the creator page, and the web wizard's
  stylesheets and components. Shared widgets outside the creator are not
  touched; `StudioTheme` wraps the page so Material defaults follow.
- **Styled boxes.** The three profile boxes become styled (macro-coloured)
  boxes when a generated card arrives, built with their text, like the
  greeting boxes; never at construction (spell-check timers vs the Linux
  goldens).

Files, routes and tests per stream: `~/.claude/plans/creator-profile-step.md`
(local) carries the live status and the ordered steps.

---

## Out of scope (later PRs)

- PR 2: editable, reorderable, voice-aware interview questions with the
  revised eleven-question set and the twelve-question cap.
- PR 3: creator templates (library folder, Mode-step picker, Save as
  template, the fourteen archetypes as built-ins, relay routes, phone).
