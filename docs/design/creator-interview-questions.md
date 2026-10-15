# The interview asks your questions, in the voice you chose

Part 2 of the AI Character Creator overhaul (part 1:
[creator-profile-step.md](creator-profile-step.md); part 3: creator
templates). Approved with the same sketch, 2026-10-13.

## Overview

The creator interviews the character before it writes the profile, and every
answer reaches every later step. Until now the questions were fixed in code
and always asked in the first person, whatever Narrative voice the user had
chosen for the card. Now the Output settings on both surfaces carry an
**Interview** card: the standard eleven questions, each editable, reorderable
by its handle, removable, with "Add a question" up to twelve and "Reset to
the standard questions". The questions, and the answers, follow the Narrative
voice selector above the card: first or third person, present or past, with
pronouns from the Sex field.

## Decisions (settled by the sketch; do not re-open)

### The standard set, in order

1. Voice: two quick samples, to someone they want to impress and to someone
   they trust.
2. What they want today, and what they want life to look like a year on.
3. The wound: a shaping moment, what it left them afraid of, what they hide
   because of it, how they steer people away when they get close to it.
4. The relationship to `{{user}}` (asked only when a relationship is set).
5. How they treat someone just met versus someone trusted.
6. Cornered or truly angered: what they actually do, shown not told.
7. Around someone they are starting to like: how they act, how they make sure
   that person never guesses, what they actually say.
8. Genuine joy or peace that lets the guard down, and the small ordinary thing
   that puts them off every time.
9. How they live: money, an ordinary day, what they never skip.
10. Sex and intimacy (asked only when 18+ is on).
11. Physical appearance, bearing, what they wear and carry in the opening
    scene.

Twelve is the cap; the two conditional rows count. Zero rows means no
interview: the profile is written from the settings alone, and no later
reader assumes a transcript.

### Voice

A standard question has a first-person and a third-person form; the third
person form takes its pronouns from the Sex field (she / he / they) through
the existing `NarrativePronouns`. The interview seed tells the model the same
voice and tense, and in the third person to quote the character's own words
when they speak. The pill on the card reads `Answered in {first|third}
person, {present|past}`.

### Edits

A row is `{key, text, condition}`: a standard row has a key and renders for
the current voice; once the user types in it, `text` is set and the row is
kept as written whatever the voice does later (`Edited · kept as written`).
A conditional row keeps its condition through an edit and cannot be removed;
its pill says when it is asked. New rows are custom rows with no condition.
Reset restores the eleven standard rows and drops every custom row and edit.

### Where it lives

Directly after the card that holds the Narrative voice selector: the Output
settings card on each desktop Configure step (Guided, Automated, Quick), and
the end of the phone's Output step. The sketch's dimmed "Narrative voice" row
stands for that existing selector.

### Persistence and transport

The desktop keeps the list with the other creator preferences and restores it
when the creator opens. `GenRunInputs.interviewQuestions` carries it through
the engine, the relay's pending-run file and the `creator_inputs` stamp; the
phone sends it in the create body (`interviewQuestions`, additive; absent is
the standard set). AI Enhance and Scene Guests use the standard set in their
own voice and have no editor.

### Both surfaces

The card is identical on the desktop and the phone apart from width: the
phone drops the handle column's cursor and drags by pointer, stacks the
header, and renders its text areas at 16px.

## Tests (proven red first)

- Rendering: each standard question in first person; in third person for
  she, he and they (no "they's", no bare "they wants"); the relationship text
  inserted; conditional rows dropped when the relationship is empty or 18+ is
  off; a custom row verbatim; the cap; an empty list yields no interview call
  and no transcript.
- The interview seed states the voice and tense; the enricher, facts pass and
  greeting readers accept an empty transcript.
- Desktop: the card renders eleven rows with the two conditional pills; typing
  marks a row edited; voice change re-renders only unedited standard rows;
  remove, add up to twelve, reset; reorder by handle; the list survives a
  restart; the three Configure steps all show it; the transcript row hides
  when there are no questions.
- Relay: `interviewQuestions` in the create body reaches the generator and the
  stamp; a pending run restored after a relay restart keeps it; a body without
  it runs the standard set.
- Web: form, payload, the card's states, the Output step in each mode; a
  Playwright journey edits a question, reorders by drag, generates with the
  scripted backend and sees the edited question in the Profile step's
  transcript.

## Files

Filled from the implementation plan (see the PR).
