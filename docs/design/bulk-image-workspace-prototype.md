# Bulk image workspace prototype

The **Images** navigation entry offers Prepare, Queue, and Review views on
desktop and web. Generation belongs to an app service, so navigating away
does not stop the queue. The desktop app must remain open.

## Prepare

Select several characters and choose the save destination:

- **Primary portrait:** replaces the character's portrait only after review
  and an explicit replacement confirmation.
- **Expressions:** prepares the Starter eight or Full 28 expressions, optionally only
  missing labels, using the existing expression prompts and shared rule editor.
- **Additional portraits:** saves situational images to the character gallery.
  These remain separate from both the primary portrait and expressions, even
  when a character has no usable primary portrait.

The prompt accepts `{character}` for each character's name. Additional and
primary images can use the current portrait as an Edit source. Sources,
prompts, seeds, and destination identities are captured during preparation.

Character selection shows small portrait previews and library folder breadcrumbs.
Search matches both character names and folder paths, including nested folders.
The web picker requests the whole library rather than only the root folder.

Expand **Generation settings** to configure the shared Image Studio desk inline.
Its graph and model controls follow the chosen operation: expression packs use
Edit where supported, or Create/img2img on backends without an Edit path. No
separate Studio modal or page is needed. These remain shared app settings.

For expressions, **Prompt rules** reuses the existing preview/editor. It starts
with global defaults; **Use for this pack** creates a local override for the next
preparation. The editor can save global defaults, and **Follow global prompt
rules** removes the local override. Previews use the first selected character.
Prepared jobs retain their effective prompts when rules change later.

## Run and review

Requests run sequentially under the existing image-generation lock. Pause
finishes the current request. Completed candidates can be kept, discarded,
or retried while later requests generate. A retry is added to the next pass
with an editable prompt and an optional new seed; it retains the original
candidate. Save kept imports only selected results.

The queue and candidate files persist in the active data directory's
`ImageBatches` folder. A request interrupted by app exit is marked interrupted
rather than submitted again automatically. Gallery imports use the job's
identity to avoid duplicate entries when saving is retried. Primary replacements
keep the canonical portrait filename and raw card metadata. Results cannot be
saved to deleted characters. Moving the data directory carries the queue,
source images, and candidates; busy batch work refuses the move before the
database closes. A manifest write failure leaves the request recoverable.

Preparation checks its settings across readiness and source capture. If another
Studio changes them, preparation refuses the pass. Remote model normalization
may also change the settings; prepare again after reviewing the selected model.
The web queue refreshes while preparation, saving, or generation is active.

## Prototype boundaries

- One queue and the existing Image Studio configuration; no named batches or
  independent generation profiles yet. A configuration fingerprint pauses
  waiting jobs when settings differ. It does not restore a configuration.
- Per-request strength editing, richer character filters, and source comparison
  are future iterations. Local rules belong to the open preparation draft;
  queued jobs persist their effective prompts. Strength comes from Image Studio
  settings; existing model-specific handling still applies.
- Expression candidates are added as gallery entries with their labels;
  existing expressions are not deleted. Only-missing is the default.
- Discard hides a request but retains its artifacts. Artifact cleanup,
  storage budgeting, and queue export are not implemented.
- Primary saves preserve existing character-card metadata using the current
  portrait writer. Its existing size limits remain in effect.

## Local checks

1. Open Images, expand Generation settings, and prepare additional portraits for
   two synthetic characters. Verify the destination and captured prompts.
2. Start, leave the page, return, and pause after the current image. Confirm
   completed candidates remain available and waiting requests stay queued.
3. Keep and save one candidate. Confirm it appears among additional portraits
   and the primary portrait is unchanged. Retry another with a changed prompt.
4. Restart before another pass. Confirm the queue loads without automatically
   sending interrupted requests. Change model settings and verify waiting work
   refuses to run under a different configuration.

The isolated demonstration uses temporary storage, a test database, mock
preferences, and a synthetic image producer. It exercises production queue,
UI, and web routes; it does not validate model quality or an external backend.
Build the web bundle, set `FPAI_REVIEW_IMAGES` to an output folder, and run
`flutter test integration_test/image_batches_options_demo.local_poke.dart -d windows`
for Full-set, prompt-rule, inline-settings, and folder-picker captures.
The local capture driver is ignored by Git, following the repository's local
poke convention.

## Review verification

Independent code reviews covered queue lifecycle, prompt rules, and character
save destinations. New regression files cover metadata and filename retention,
deleted-character refusal, filesystem write failure, generation lock ownership,
settings changes during preparation, relocation/restart, lazy queue loading
during relocation, and web refresh races. Existing tests were not edited.

Before publication, register `/images` in the existing browser sweep and add
its journey to the existing journey suite. Those test edits require the
maintainer's `approved-test-change` label. An actual configured backend smoke
run is still needed to validate external generation alongside the synthetic
workspace checks.
