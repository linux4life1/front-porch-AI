# Creator templates: every box, the way you saved it

Part 3 of the AI Character Creator overhaul (part 1:
[creator-profile-step.md](creator-profile-step.md); part 2:
[creator-interview-questions.md](creator-interview-questions.md)). Approved
with the same sketch, 2026-10-13: "keep templates for the AI character
creator, so you're not always starting at square one every time."

## Overview

A template is a named snapshot of the creator's whole form, in every step,
except the character's name and the Setup step's backend and model. It is a
JSON file in the library, `<library>/chargen/templates/<slug>.json`, the way
the KoboldCpp presets are files in their folder: list, save, rename, delete,
a broken file listed and never thrown on. The Mode step on both surfaces
opens with **Start from a template**: your templates newest first, then the
built-in archetypes, then "All 15 built in". Loading one fills the form and
marks the Configure step "Started from"; **Save as template** writes the
form back under a name, replacing a template of the same name.

## Decisions (settled; do not re-open)

### What a template holds

One canonical, flat JSON form (`version: 1`) defined once in
`lib/services/chargen/creator_template_schema.dart`, with a default for
every key. Both surfaces map to and from it: the desktop from
`CreatorState` (the same fields `CreatorFormPrefs` saves), the phone from
`ChargenForm`. A key one surface does not know survives the other's save:
saving merges the incoming keys over the stored file (and over the
template it was started from), so a template made on the desktop keeps its
art style after a phone edit. Precedence, lowest first: the stored file,
then the template it was started from (`basedOn`), then the incoming form.
So saving a built-in's edit over an older template of the same name takes
the built-in's other keys, and a key the form carries always wins.

In: the mode and each mode's inputs (Automated's archetype and bubbles,
Guided's vision and every section, Quick's concept and scenario), the
interview rows (null is the standard set), output settings (greeting
length, alternates, tones, detail, perspective, tense, Sex, age), lore
settings and URLs, 18+ and its lists, relationships, art style, dynamic
macros, the reasoning toggle. Out: the name, the Setup step, lore files
(bound to one machine; loading clears them), the Realism step and
everything after it (those belong to the card, not the form).

Where the surfaces differ: the desktop has one concept box for Quick and
Automated where the phone has two, so the desktop writes both canonical
keys from its box and reads the active mode's; Quick's own tones, count and
18+ on the desktop are saved from the active mode and filled on both sets
on load. A phone template re-saved on the desktop loses the inactive
mode's concept if the two differed; accepted.

### Built-ins

The fifteen archetypes (`kArchetypePresets`, moved from the creator's
options into `lib/services/chargen/`) are read-only templates: Automated
mode with the archetype applied, a blurb from the archetype's keywords,
the "Built in" pill, no rename or delete, and a name you cannot save over.
Tsundere and Kuudere come first, then the rest in their usual order.
Loading a built-in fills the whole form from the defaults plus the
archetype; it never fills an empty name.

### Names

The slug is the lowercased name with runs of letters and digits joined by
hyphens, at most 48 characters, with a short hash appended when the name
has characters outside ASCII or would otherwise collide; Windows device
names get a suffix. Name problems, in order: empty ("Give the template a
name."), over 80 characters ("Keep the name to 80 characters or fewer."),
a built-in's name ("{Name} is a built-in template and can't be changed.
Give yours another name."). Rename refuses a taken name ("Another template
already has this name."). Saving a name that exists replaces it, with the
caption "A template with this name already exists. Saving replaces it."

### Started from

Loading records the template; the Configure step (desktop) and the Output
step (phone) show "Started from: {name}" with "Changes stay on this form
until you save them to the template." and the Save as template button. The
mark clears on Clear Everything, after Save & Finish, and when the template
is deleted; a rename follows the new name. It is saved with the
preferences so a restart keeps it.

### Dialogs

Save and Rename use the spec's Dialog (phone: a bottom sheet with the
handle); Delete confirms through `showWarmDialog`; "All 15 built in" opens
a picker of the fifteen. The shared warm dialog reads the creator palette
when it is open inside the creator, so these dialogs match the spec without
a second dialog primitive.

### Relay

`GET /api/chargen/templates` (yours newest first, then built-ins, each with
its summary and form; a broken file carries its problem), `PUT
/api/chargen/templates/<slug>` with `{name, form, basedOn?}` (create or
replace; 400 for a name problem or a slug that does not match the name;
409 for a built-in), `POST …/<slug>/rename`, `DELETE …/<slug>` (404
missing, 409 built-in). The desktop and the relay use the one library on
the one folder.

### Housekeeping this PR carries

The preferences did not save Quick's own tones, count and 18+, the
archetype, the reasoning toggle or the lore URLs, and Clear Everything did
not reset the Quick fields or the toggle; the prefs ↔ template ↔ Clear
Everything round trip needs them, so they are fixed here. Templates are
not in the automatic backups, which copy the database only, the same as
the KoboldCpp presets.

## Tests (proven red first)

- Library: save, list newest first, rename moves the file, delete; broken
  files listed and never thrown; the merge keeps unknown keys and
  `basedOn` carries them; the name key is never stored; slug, problem,
  summary and saved-label vectors from one fixture both surfaces read;
  built-ins counted against the label, featured first, refused on save,
  rename and delete; a link in the folder is neither listed nor read; a
  save replaces an empty folder in its place; a replace that fails leaves
  the old copy where it was and the new bytes in the temp file.
- Relay: the list's order, summary and form; PUT create, replace, 400, 409;
  rename and delete with 404; a library save shows in GET and a PUT is read
  by the library.
- Desktop: the Mode step's card and order; Load fills every key, sets the
  mode, leaves the name, shows the pill in all three modes; Save keeps the
  phone's keys, prefills, shows the replace caption, refuses a built-in;
  the menu's Rename and Delete with confirmation; the picker; Clear
  Everything and a restart keep or clear every template field.
- Web: the round trip of every phone key, the picker, the menu, the
  sheets, the PUT body; a journey that loads a desktop-made template on
  the phone, saves it back, sees the desktop-only key kept, renames and
  deletes it.

## Files

- Schema and data: `lib/services/chargen/creator_template_schema.dart`
  (the canonical form, its surfaces, the merge, slug and name rules, the
  shared copy), `creator_template.dart` (`CreatorTemplate`,
  `TemplateSummary`, the built-ins), `archetype_presets.dart` (the
  archetype data, moved out of the desktop's options so the built-ins and
  both surfaces read one copy).
- Library: `lib/services/chargen/creator_template_library.dart`, the
  files under `<library>/chargen/templates/`: list, read, save
  (`basedOn`), rename, delete, each refusal with the relay's status. The
  writes go one at a time per folder, each to a temp file renamed into
  place; the old copy is only moved aside, never deleted first.
- Relay: `lib/services/web/routes/chargen_template_routes.dart` and
  `facade/chargen_facade.dart`.
- Desktop: `lib/ui/character_creator/creator_templates.dart` (the list,
  Load, Save, Rename, Delete and the started-from mark),
  `creator_state/creator_template_form.dart` (`CreatorState` to and from
  the form), `creator_state.prefs.dart` (the mark and the fields the
  round trip needed), `creator_state/creator_form_reset.dart`;
  `widgets/template_picker_card.dart`, `template_tile.dart`,
  `template_name_dialog.dart`, `template_dialogs.dart`,
  `creator_config_header.dart`; `steps/mode_select_step.dart` and the
  three Configure steps; `widgets/mode_card.dart` (the spec's grid);
  `lib/ui/widgets/warm_dialog.dart` reads the creator palette inside the
  creator; `lib/ui/theme/studio_colors.dart` adds the scrim.
- Web: `web_ui/src/components/aichargen/templatesApi.ts`,
  `templateForm.ts` (`ChargenForm` to and from the form),
  `TemplatePicker.tsx`, `TemplateSheets.tsx`, `TemplateSaveBar.tsx`,
  `styles/creator-templates.css`; `pages/CreateAiCharacterPage.tsx`
  wires them; `library/CardMenu.tsx` gained a danger item.
- Tests: `test/services/chargen/creator_templates_test.dart`,
  `test/services/web/chargen_greeting_routes_test.dart` (the relay
  group), `test/ui/character_creator/creator_templates_test.dart`, the
  Mode and Configure goldens, `web_ui/src/components/aichargen/*.test.*`,
  `web_ui/e2e/journeys.spec.ts`, and the fixture both surfaces read,
  `test/fixtures/chargen/creator_template_vectors.json`.
