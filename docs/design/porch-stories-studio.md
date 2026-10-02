# Porch Stories — the Studio engine

Porch Stories was forked from WriteforMe (now EllipsisProse, Apache-2.0,
credited in `NOTICE`) in March 2026. Upstream has since grown review loops,
an eight-sequence structure, character interviews, a continuity ledger,
relationship tracking, narrative lenses, prose quality checks and a Director.
This document records how that design was brought into the Dart engine, and
the decisions that differ from upstream. Nothing was copied: upstream is one
34,000-line browser script; ours is a second engine mode beside the original.

## Two engines, one project blob

`StoryProject.engineMode` is `quick` (the original pipeline, untouched in
shape) or `studio`. Every public `StoryPipelineService` operation dispatches
on it (`story_pipeline_service.api.dart`), so the story pages and the web
facade call the same methods for both. Stories are still one JSON blob per
row; every Studio field is additive and `StoryProject.normalize()` repairs
invariants on load and save (scene ids, one sequence per act for Quick).

## Structure

Scenes stay in `scenes[actIdx]` keyed by index, beats in `"act-scene"`, prose
in `"act-scene-beat"`. A **sequence** is a contiguous run of scenes inside an
act (`StoryScene.sequence`, `project.sequences`), so adding the sequence layer
never re-keyed the maps. Scenes carry a stable `id`; continuity facts and
relationship history point at ids, so inserting or removing scenes (the
Director) does not move the past. `StoryStructure` is the one place that
splices scenes or beats and re-keys the maps after it.

Studio always builds three acts and eight sequences (2 / 4 / 2 — the Frank
Daniel model upstream uses). Quick keeps 1–5 acts. Scene and beat budgets come
from `StoryPacing.forTarget(words)` and actually add up to the target:
8 × scenes × beats × 400 words per beat. Upstream's defaults
(6–16 scenes × 12–45 beats × 200 words) overshoot its own target several
times over; the Engine step shows the real numbers.

## Stages (Studio)

| Stage | Role | Gate |
|---|---|---|
| World & cast (`foundation`) | planning | status quo + ≥1 brief |
| Interview (lead cast, ≤6) | prose | interview ≥200 chars |
| Story arc | planning | inciting incident + threads; reviewed |
| Acts | planning | exactly 3; reviewed |
| Sequences | planning | exactly 8; act from the slot, not the model; reviewed |
| Scenes (per sequence) | planning | ≥ budget min; reviewed |
| Beats (per scene) | planning | ≥ budget min; reviewed |
| Write (per beat) | prose | ≥60 words |
| Continuity check → surgical fix | review | FAIL → find/replace edits, change ratio ≤0.6, else one rewrite |
| Banned-phrase scrub | review | only when a beat has >2 hits |
| Archivist (per scene) | review | facts, relationship moves, summary |
| Sequence summary | review | once every scene of the sequence is written |

`_agent()` (`story_pipeline_service.agent.dart`) is the loop: generate, gate
in code, review with a second call, feed the objection back, three tries, the
last try always on the main model. A reviewer that rejects every try does not
dead-end the story: the last structurally valid answer is used.

Replies are tags (`StoryXml`), never JSON: a lost comma ruins a JSON reply,
a tag reply loses one field. Quick's planning stages were switched to tags
too (`StoryQuickXml`), with the JSON parser as the fallback so a model that
still answers in JSON keeps working.

## Memory

- `StoryContinuity` — facts with "true from scene X", retired by a newer fact
  about the same subject; the writer sees what is known going into a scene.
- Relationships — directed `from → to` rows with feeling, note, unspoken
  tension, trust 0–10 and a history of shifts anchored to scenes.
- Story so far — assembled from per-scene summaries (archivist) and per-
  sequence condensations; never stale after an edit.
- Lore search — `StoryLoreIndex` uses the in-process embedding model when
  it is set up, word overlap otherwise, so lore reaches the writer either way.
  Vectors are cached in memory, not stored.
- Run log and the Director's undo snapshot live beside the story under
  `<storage root>/story_studio/<id>/`, not in the blob (`StoryStudioStore`).

## Model lanes

Each story points planning, prose and review at the main or the worker model
(`StoryLanes`, wired in `story_pipeline_factory.dart`). Worker calls hold the
worker lane so a shared GPU can swap. No worker → everything on main.

## Director

`DirectorPrompts.planner` sees a one-page outline (labels like `3.2`, what is
written) and returns actions; `StoryDirector.parsePlan` resolves labels to
scene ids and drops anything it cannot place. Structural actions are pure
code (`StoryDirectorApply`); prose actions become follow-ups: a surgical
patch (edits located per beat), a rewrite, or fresh prose for an inserted
beat. Touched scenes are re-archived. "Protect written prose" locks the
destructive set (delete / move / beat changes / rewrite) on written scenes;
`modifyScene` and `editProse` patch lines and stay open. Apply snapshots the
project first; Undo restores it via `StoryRepository.replaceProject`.

## Stop

`requestStop()` sets a flag and aborts the in-flight HTTP call; `_guard`
spans the outermost operation and turns the resulting
`StoryStoppedException` into a quiet "Stopped" status. Everything saved so
far stays.

## Surfaces

Desktop: `lib/ui/story_studio/` (shell sidebar, sections, shared widgets),
`story_setup/engine_step.dart`, the embedded structure/writer pages, the
reader's scroll part. Web: `web_ui/src/pages/story/StudioShell.tsx` and the
story pages; every number the web shows (quality chips, pacing, lane labels,
lenses) comes from `/api/stories/*` so the engine is not duplicated. Scene
labels and "what is written" are presentation and are mirrored in
`storyShape.ts`.

## Tests

- `test/services/story/studio_leaves_test.dart` — the pure leaves.
- `test/services/story/studio_pipeline_test.dart` — the real pipeline with a
  stage-aware scripted model: a bounced arc, a continuity slip patched, Stop,
  and a Director plan applied and undone.
- `integration_test/story_studio_test.dart` — the whole thing through the
  UI against the sandboxed fake backend (`fake_backend_studio.dart` routes on
  the prompts' role constants).
- `integration_test/story_pipeline_test.dart` picks Quick on the Engine step
  and pins the original pipeline as before.
