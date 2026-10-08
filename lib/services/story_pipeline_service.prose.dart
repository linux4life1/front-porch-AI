// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

part of 'story_pipeline_service.dart';

/// Per-beat prose + QC — Drafter/Editor, Archivist, Beat Validator, and the
/// Auto-Write orchestrator. Extracted verbatim from `story_pipeline_service.dart`
/// (Cluster G of the god-file split) as a public-named extension (see the
/// ChatService-parts precedent — the writer page calls `autoWriteScene`
/// directly, so a private extension would hide it).
extension StoryPipelineProse on StoryPipelineService {
  /// Stage 5+6: Drafter + Editor — beat → prose.
  Future<void> _quickDraftAndEdit(
    StoryProject project,
    int actIndex,
    int sceneIndex,
    int beatIndex,
  ) async {
    _isRunning = true;
    final sId = '$actIndex-$sceneIndex';
    final bId = '$sId-$beatIndex';

    try {
      // These reads MUST stay inside the try: only the `finally` below clears
      // `_isRunning`, so a stale index (a deep-linked web writer URL, or a beat
      // list the validator shortened mid-run) escaping here latched the flag on
      // and froze every story page on the spinner until app restart.
      final sceneBeats = project.beats[sId];
      final actScenes = project.scenes[actIndex];
      if (sceneBeats == null ||
          beatIndex < 0 ||
          beatIndex >= sceneBeats.length ||
          actScenes == null ||
          sceneIndex < 0 ||
          sceneIndex >= actScenes.length) {
        _setStatus('Drafter', 'That beat is no longer part of this scene.');
        return;
      }
      final beat = sceneBeats[beatIndex];
      final scene = actScenes[sceneIndex];

      _setStatus('Drafter', 'Writing beat ${beatIndex + 1}: ${beat.type}...');

      // Gather context
      final prevBeatText = beatIndex > 0
          ? project.prose['$sId-${beatIndex - 1}']?.final_ ?? ''
          : '';
      final nextBeat = beatIndex + 1 < (project.beats[sId]?.length ?? 0)
          ? project.beats[sId]![beatIndex + 1]
          : null;

      // Build character voices
      final voices = scene.castNames
          .map((name) {
            final char = project.cast.where((c) => c.name == name).firstOrNull;
            return char != null
                ? '${char.name} (${char.role}): ${char.description}'
                : name;
          })
          .join('\n');

      // Build drafter prompt
      final drafterPrompt =
          '''${StoryPrompts.drafter(project)}

## Scene: ${scene.title}
${scene.description}

## Current Beat (${beat.type})
${beat.description}

## Emotional Shift: ${beat.emotionalShift}
## Pacing: ${beat.pacing == 0
              ? 'SLOW — atmospheric, sensory details'
              : beat.pacing == 1
              ? 'BALANCED — dialogue-heavy'
              : 'FAST — action, rapid decisions'}
## Valence: ${beat.valence}

## Characters Present
$voices

## Style & Tone
${project.style.writingGuide}

${StudioProsePrompts.bannedBlock(project)}

${prevBeatText.isNotEmpty ? '## Previous Beat Text (continue from here)\n$prevBeatText' : '## This is the FIRST beat of the scene.'}

${nextBeat != null ? '## Next Beat Preview (end just before this)\n${nextBeat.description}' : '## This is the LAST beat of the scene. Bring it to a satisfying close.'}

Write the prose now. Return ONLY the prose text, no commentary.''';

      // Reasoning models leak <think> blocks into the content channel (the
      // prompt only *asks* them not to), and this text is stored as the
      // beat's prose — shown in the reader, exported, and fed back into the
      // Editor prompt. Strip it here exactly like the whole-act writer does.
      final draft = StoryJson.stripThinkTags(
        await _callLLM(
          drafterPrompt,
          maxLength: 1024,
          stage: StoryStageParams.prose,
          project: project,
          role: StoryRole.prose,
          label: 'Drafter',
        ),
      ).trim();

      // Store draft
      project.prose[bId] = BeatProse(draft: draft);
      _notify();

      // Editor pass
      _setStatus('Editor', 'Polishing beat ${beatIndex + 1}...');

      final editorPrompt =
          '''${StoryPrompts.editor(project)}

## Context
Scene: ${scene.title}
Beat: ${beat.description}
Previous beat text: ${prevBeatText.isNotEmpty ? prevBeatText.substring(0, (prevBeatText.length).clamp(0, 500)) : 'Start of scene'}
${nextBeat != null ? 'Next beat plan: ${nextBeat.description}' : 'This is the final beat.'}

## Draft to Polish:
$draft

Return ONLY the polished prose text.''';

      final edited = StoryJson.stripThinkTags(
        await _callLLM(
          editorPrompt,
          maxLength: 1024,
          stage: StoryStageParams.editing,
          project: project,
          role: StoryRole.prose,
          label: 'Editor',
        ),
      ).trim();
      project.prose[bId] = BeatProse(draft: draft, final_: edited);

      await _repository.saveProject(project);
      _setStatus('Editor', 'Beat ${beatIndex + 1} complete!');
    } catch (e) {
      _setStatus('Editor', 'Error: $e');
      rethrow;
    } finally {
      _isRunning = false;
      _notify();
    }
  }

  /// Stage 7: Archivist — update cast/lore after prose is written.
  Future<void> _quickArchivist(
    StoryProject project,
    int actIndex,
    int sceneIndex,
  ) async {
    _isRunning = true;
    _setStatus('Archivist', 'Archiving world updates...');

    try {
      final sId = '$actIndex-$sceneIndex';
      final sceneText = StringBuffer();
      for (int i = 0; i < (project.beats[sId]?.length ?? 0); i++) {
        final prose = project.prose['$sId-$i'];
        if (prose?.final_ != null) sceneText.writeln(prose!.final_);
      }

      if (sceneText.isEmpty) return;

      final prompt =
          '''${StoryPrompts.archivist(project.promptTier)}

## Text to Analyze:
${sceneText.toString().substring(0, sceneText.length.clamp(0, 3000))}

## Current Cast: ${project.cast.map((c) => c.name).join(', ')}
## Existing Lore: ${project.lore.map((l) => l.topic).join(', ')}''';

      final response = await _callLLM(
        prompt,
        maxLength: 2048,
        project: project,
        label: 'Archivist',
      );
      final json = StoryQuickXml.parse('archivist', response);

      if (json != null) {
        // Apply cast updates
        if (json['cast_updates'] != null) {
          for (final up in json['cast_updates'] as List) {
            final name = up['name'];
            final idx = project.cast.indexWhere((c) => c.name == name);
            if (idx != -1) {
              final char = project.cast[idx];
              if (up['append_history'] != null) {
                char.details['history'] =
                    '${char.details['history'] ?? ''}\n${up['append_history']}';
              }
              if (up['append_story_events'] != null) {
                char.details['story_events'] =
                    '${char.details['story_events'] ?? ''}\n- ${up['append_story_events']}';
              }
              if (up['update_goals'] != null) {
                char.details['goals'] = up['update_goals'];
              }
            }
          }
        }

        // Apply lore updates
        if (json['lore_updates'] != null) {
          for (final up in json['lore_updates'] as List) {
            final entry = StoryLoreEntry.fromJson(up);
            entry.validFromAct = actIndex + 1;
            entry.validFromScene =
                (project.scenes[actIndex]?.indexOf(
                      project.scenes[actIndex]!.firstWhere(
                        (s) => true,
                        orElse: () => project.scenes[actIndex]!.first,
                      ),
                    ) ??
                    0) +
                1;
            if (!project.lore.any((l) => l.topic == entry.topic)) {
              project.lore.add(entry);
            }
          }
        }

        await _repository.saveProject(project);
      }

      _setStatus('Archivist', 'World updated!');
    } catch (e) {
      _setStatus('Archivist', 'Error: $e');
      // Non-fatal — don't rethrow
    } finally {
      _isRunning = false;
      _notify();
    }
  }

  /// Stage 8: Beat Validator — check continuity.
  Future<bool> runBeatValidator(
    StoryProject project,
    int actIndex,
    int sceneIndex,
    int beatIndex,
  ) async {
    final sId = '$actIndex-$sceneIndex';
    final nextBeatIndex = beatIndex + 1;
    if (nextBeatIndex >= (project.beats[sId]?.length ?? 0)) return true;

    _setStatus('Validator', 'Checking continuity...');

    try {
      final prose = project.prose['$sId-$beatIndex']?.final_ ?? '';
      final nextBeat = project.beats[sId]![nextBeatIndex];
      final scene = project.scenes[actIndex]![sceneIndex];

      final prompt =
          '''${StoryPrompts.beatValidator(project.promptTier)}

Scene Goal: ${scene.description}
Written Prose Summary: ${prose.substring(0, prose.length.clamp(0, 500))}
Next Beat Plan: ${nextBeat.description}''';

      final response = await _callLLM(
        prompt,
        maxLength: 2048,
        project: project,
        label: 'Beat Validator',
      );
      final json = StoryQuickXml.parse('validator', response);

      if (json != null &&
          json['valid'] == false &&
          json['rectified_beats'] != null) {
        // Replace future beats with rectified versions
        final rectified = (json['rectified_beats'] as List)
            .map((b) => StoryBeat.fromJson(b))
            .toList();

        final currentBeats = project.beats[sId]!;
        final keptBeats = currentBeats.sublist(0, beatIndex + 1);
        project.beats[sId] = [...keptBeats, ...rectified];

        await _repository.saveProject(project);
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('[StoryPipeline] Validator error: $e');
      return true; // Continue if validator fails
    }
  }

  /// Auto-write all beats in a scene sequentially.
  Future<void> _quickAutoWriteScene(
    StoryProject project,
    int actIndex,
    int sceneIndex,
  ) async {
    final sId = '$actIndex-$sceneIndex';
    if (project.beats[sId]?.isEmpty ?? true) return;

    // The length is re-read every iteration on purpose: runBeatValidator
    // REPLACES project.beats[sId] with a different list (kept + rectified
    // beats), so a captured local goes stale — it either overran the new,
    // shorter list or silently dropped the tail of a longer one.
    //
    // The ceiling is what keeps that re-read safe: a model that answers
    // "still invalid, here are three more beats" every single time grows the
    // list exactly as fast as the loop consumes it, and nothing in this loop
    // is cancellable, so the user would watch it burn tokens forever. A scene
    // is a handful of beats; this only ever trips on a runaway.
    final beatCeiling = (project.beats[sId]?.length ?? 0) + 24;
    project.autoBannedPhrases = StoryQuality.overusedPhrases(
      StoryQuality.recentProse(project, actIndex, sceneIndex),
      exclude: [...project.cast.map((c) => c.name), ...project.bannedPhrases],
    );
    for (
      int i = 0;
      i < (project.beats[sId]?.length ?? 0) && i < beatCeiling;
      i++
    ) {
      final bId = '$sId-$i';
      if (project.prose[bId]?.final_ != null) continue; // Skip already written

      await _quickDraftAndEdit(project, actIndex, sceneIndex, i);
      // runDraftAndEdit clears _isRunning in its own `finally`, but the scene
      // is not finished — re-arm so the validator/next-beat stretch still
      // reads as busy in the UI (same reset as generateFullAct's stages).
      _isRunning = true;

      // Run validator after each beat (except the last)
      if (i < (project.beats[sId]?.length ?? 0) - 1) {
        await runBeatValidator(project, actIndex, sceneIndex, i);
      }
    }

    // Run archivist after the full scene
    await _quickArchivist(project, actIndex, sceneIndex);
  }
}
