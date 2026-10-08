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

/// Applying a Director plan: structural changes in code, then the prose
/// work each one asked for, then a re-archive of every scene that changed.
extension StoryPipelineDirectorApply on StoryPipelineService {
  Future<void> applyDirectorPlan(StoryProject project) => _guard(() async {
    final plan = project.directorPlan;
    if (plan == null) return;
    final todo = plan.actions.where((a) => a.enabled && !a.locked).toList();
    if (todo.isEmpty) return;
    _isRunning = true;
    try {
      final id = project.dbId;
      if (id != null) await store.saveUndo(id, project.toJsonString());

      final touched = <String>{};
      var applied = 0;
      for (final action in todo) {
        _setStatus('Director', 'Applying: ${action.summary}');
        try {
          final outcome = StoryDirectorApply.apply(project, action);
          if (outcome.error != null) {
            action.result = 'failed: ${outcome.error}';
          } else {
            await _directorProse(project, outcome, touched);
            action.result = 'applied';
            applied++;
          }
        } on StoryStoppedException {
          rethrow;
        } catch (e) {
          action.result = 'failed: $e';
        }
        await _repository.saveProject(project);
      }

      for (final sceneId in touched) {
        final ref = project.findScene(sceneId);
        if (ref == null) continue;
        final count =
            project
                .beats[StoryProjectShape.sceneKey(ref.act, ref.index)]
                ?.length ??
            0;
        if (count > 0 && project.beatsWritten(ref.act, ref.index) == count) {
          await _studioArchive(project, ref.act, ref.index);
        }
      }

      project.directorApplied = DirectorApplied(
        directive: plan.directive,
        changeCount: applied,
      );
      await _repository.saveProject(project);
      _setStatus(
        'Director',
        '$applied change${applied == 1 ? '' : 's'} applied.'
            '${applied < todo.length ? ' ${todo.length - applied} could not be.' : ''}',
      );
    } catch (e) {
      _setStatus('Director', 'Error: $e');
      rethrow;
    } finally {
      _isRunning = false;
      _notify();
    }
  });

  Future<void> _directorProse(
    StoryProject project,
    DirectorOutcome outcome,
    Set<String> touched,
  ) async {
    if (outcome.followUp == ProseFollowUp.none) return;
    final ref = project.findScene(outcome.sceneId);
    if (ref == null) return;
    final act = ref.act;
    final index = ref.index;
    final count =
        project.beats[StoryProjectShape.sceneKey(act, index)]?.length ?? 0;
    touched.add(outcome.sceneId);

    switch (outcome.followUp) {
      case ProseFollowUp.none:
        return;
      case ProseFollowUp.patch:
        await _directorPatch(project, act, index, outcome);
      case ProseFollowUp.rewrite:
        final beats = outcome.beat >= 0
            ? [outcome.beat]
            : [for (var b = 0; b < count; b++) b];
        if (outcome.beat < 0) {
          StoryStructure.clearSceneProse(project, act, index);
        } else {
          project.prose.remove(
            StoryProjectShape.beatKey(act, index, outcome.beat),
          );
        }
        for (final b in beats) {
          if (b < count) {
            await _studioWriteBeat(
              project,
              act,
              index,
              b,
              directive: outcome.instruction,
            );
          }
        }
      case ProseFollowUp.write:
        if (outcome.beat >= 0 && outcome.beat < count) {
          await _studioWriteBeat(
            project,
            act,
            index,
            outcome.beat,
            directive: outcome.instruction,
          );
        }
    }
  }

  /// Ask for edits against the scene's prose (or one beat of it), then land
  /// each edit in whichever beat holds the words it quotes.
  Future<void> _directorPatch(
    StoryProject project,
    int act,
    int index,
    DirectorOutcome outcome,
  ) async {
    final count =
        project.beats[StoryProjectShape.sceneKey(act, index)]?.length ?? 0;
    final beats = outcome.beat >= 0
        ? [outcome.beat]
        : [
            for (var b = 0; b < count; b++)
              if ((project.beatText(act, index, b) ?? '').isNotEmpty) b,
          ];
    if (beats.isEmpty) return;
    final text = beats.map((b) => project.beatText(act, index, b)).join('\n\n');
    final label = project.sceneLabel(act, index);
    _setStatus('Director', 'Patching $label…');
    final call = await _call(
      StudioProsePrompts.patch(prose: text, instruction: outcome.instruction),
      maxLength: 2048,
      stage: StoryStageParams.editing,
      project: project,
      role: StoryRole.prose,
      label: 'Director patch $label',
      tool: StoryTools.edits,
    );
    final edits = StoryEdits.parse(call.text);
    var landed = 0;
    for (final edit in edits) {
      for (final b in beats) {
        final key = StoryProjectShape.beatKey(act, index, b);
        final prose = project.prose[key];
        final current = prose?.final_ ?? '';
        if (current.isEmpty || StoryEdits.locate(current, edit.find) == null) {
          continue;
        }
        final report = StoryEdits.apply(current, [edit]);
        if (report.changed) {
          prose!.final_ = report.text;
          landed++;
        }
        break;
      }
    }
    call.entry
      ..verdict = landed > 0 ? 'PASS' : 'FAIL'
      ..note = '$landed of ${edits.length} edit(s) landed.';
    await _log(project, call.entry);
    if (landed == 0) {
      throw StoryStageException(
        'The patch for $label could not be placed in the prose.',
      );
    }
  }
}
