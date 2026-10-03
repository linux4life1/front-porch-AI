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

/// Studio structure: three acts, eight sequences, then the scenes of one
/// sequence and the beats of one scene.
extension StoryPipelineStudioStructure on StoryPipelineService {
  Future<void> _studioActs(StoryProject project) async {
    _isRunning = true;
    try {
      final canon = await _studioCanon(project);
      final acts = await _agent(
        project,
        stage: 'Act Structure',
        tool: StoryTools.acts,
        status: 'Dividing the story into three acts…',
        validate: StudioParse.checkActs,
        prompt: (previous, feedback) => StudioStructurePrompts.acts(
          project,
          canon: canon,
          previous: previous,
          feedback: feedback,
        ),
        review: (output) => StudioStructurePrompts.actsReview(project, output),
      );
      StudioParse.applyActs(project, acts);
      await _repository.saveProject(project);

      final sequences = await _agent(
        project,
        stage: 'Sequences',
        tool: StoryTools.sequences,
        status: 'Breaking the acts into eight sequences…',
        validate: StudioParse.checkSequences,
        prompt: (previous, feedback) => StudioStructurePrompts.sequences(
          project,
          canon: canon,
          previous: previous,
          feedback: feedback,
        ),
        review: (output) =>
            StudioStructurePrompts.sequencesReview(project, output),
      );
      StudioParse.applySequences(project, sequences);
      await _repository.saveProject(project);
      _setStatus('Sequences', 'Three acts and eight sequences are ready!');
    } catch (e) {
      _setStatus('Act Structure', 'Error: $e');
      rethrow;
    } finally {
      _isRunning = false;
      _notify();
    }
  }

  /// Plan the scenes of sequence [number], replacing any it already has
  /// (and everything written for them).
  Future<void> _studioScenes(StoryProject project, int number) async {
    final sequence = project.sequenceByNumber(number);
    final act = project.actIndexForSequence(number);
    if (sequence == null || act < 0) return;
    _isRunning = true;
    try {
      final existing = project.sceneIndexesInSequence(number);
      final list = project.scenes[act] ?? const <StoryScene>[];
      var first = existing.isNotEmpty
          ? existing.first
          : list.indexWhere((s) => s.sequence > number);
      if (first == -1) first = list.length;

      final canon = await _studioCanon(project);
      final budget = StoryPacing.forTarget(
        project.targetWords,
      ).scenesFor(number);
      final text = await _agent(
        project,
        stage: 'Scenes: Sequence $number',
        tool: StoryTools.scenes,
        status: 'Outlining the scenes of "${sequence.title}"…',
        validate: (output) => StudioParse.checkScenes(output, min: budget.min),
        prompt: (previous, feedback) => StudioStructurePrompts.scenes(
          project,
          sequence,
          act: act,
          firstScene: first,
          canon: canon,
          previous: previous,
          feedback: feedback,
        ),
        review: (output) =>
            StudioStructurePrompts.scenesReview(project, sequence, output),
      );
      final scenes = StudioParse.scenes(
        project,
        text,
        sequence: number,
        // A little slack: a planner that wrote one scene too many has
        // usually written a better sequence, not a worse one.
        max: budget.max + 1,
      );
      StoryStructure.replaceSequenceScenes(project, number, scenes);
      sequence.summary = '';
      await _repository.saveProject(project);
      _setStatus(
        'Scenes: Sequence $number',
        '${scenes.length} scenes outlined for "${sequence.title}"!',
      );
    } catch (e) {
      _setStatus('Scenes: Sequence $number', 'Error: $e');
      rethrow;
    } finally {
      _isRunning = false;
      _notify();
    }
  }

  /// Plan (or re-plan) the scenes of one sequence on request.
  Future<void> planSequenceScenes(StoryProject project, int number) =>
      _guard(() => _studioScenes(project, number));

  Future<void> _studioBeats(StoryProject project, int act, int index) async {
    final scenes = project.scenes[act];
    if (scenes == null || index < 0 || index >= scenes.length) return;
    final scene = scenes[index];
    _isRunning = true;
    final stage = 'Beats: ${project.sceneLabel(act, index)}';
    try {
      final pacing = StoryPacing.forTarget(project.targetWords);
      final tail = _proseBefore(project, act, index, 0);
      final text = await _agent(
        project,
        stage: stage,
        status: 'Choreographing "${scene.title}"…',
        tool: StoryTools.beats,
        maxLength: 6144,
        validate: (output) =>
            StudioParseProse.checkBeats(output, min: pacing.beatsMin),
        prompt: (previous, feedback) => StudioProsePrompts.beats(
          project,
          act,
          index,
          previousTail: tail,
          previous: previous,
          feedback: feedback,
        ),
        review: (output) =>
            StudioProsePrompts.beatsReview(project, act, index, output),
      );
      final key = StoryProjectShape.sceneKey(act, index);
      project.prose.removeWhere((k, _) => k.startsWith('$key-'));
      project.beats[key] = StudioParseProse.beats(
        text,
        max: pacing.beatsMax + 2,
        tension: scene.tension,
      );
      await _repository.saveProject(project);
      _setStatus(
        stage,
        '"${scene.title}" broken into ${project.beats[key]!.length} beats!',
      );
    } catch (e) {
      _setStatus(stage, 'Error: $e');
      rethrow;
    } finally {
      _isRunning = false;
      _notify();
    }
  }

  /// Studio "generate this act": sequence by sequence, scene by scene —
  /// plan the scenes, then for each scene plan its beats and write it before
  /// moving on, so every later plan can see what was actually written.
  Future<void> _studioFullAct(StoryProject project, int act) async {
    if (act < 0 || act >= project.acts.length) return;
    final actNumber = project.acts[act].number;
    try {
      for (final sequence in project.sequencesInAct(act)) {
        if (project.sceneIndexesInSequence(sequence.number).isEmpty) {
          await _studioScenes(project, sequence.number);
        }
        for (final index in project.sceneIndexesInSequence(sequence.number)) {
          final key = StoryProjectShape.sceneKey(act, index);
          if (project.beats[key]?.isEmpty ?? true) {
            await _studioBeats(project, act, index);
          }
          await _studioWriteScene(project, act, index);
        }
        await _studioSequenceSummary(project, sequence.number);
      }
      _setStatus('Act $actNumber Complete', 'Ready for review');
    } catch (e) {
      _setStatus('Error', 'Act $actNumber failed: $e');
      rethrow;
    } finally {
      _isRunning = false;
      _notify();
    }
  }
}
