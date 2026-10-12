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

import 'dart:async';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/story/story.dart';
import 'package:front_porch_ai/services/story_pipeline/story_pipeline.dart';

/// Studio structure: three acts, eight sequences, then the scenes of one
/// sequence and the beats of one scene.
class StoryStudioStructure {
  StoryStudioStructure(this._ctx, this._agent, this._prose, this._memory);

  final StoryPipelineContext _ctx;
  final StoryAgent _agent;
  final StoryStudioProse _prose;
  final StoryStudioMemory _memory;

  Future<void> acts(StoryProject project) async {
    _ctx.running = true;
    try {
      final canon = await _agent.canon(project);
      final acts = await _agent.run(
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
      await _ctx.repository.saveProject(project);

      final sequences = await _agent.run(
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
      await _ctx.repository.saveProject(project);
      _ctx.setStatus('Sequences', 'Three acts and eight sequences are ready!');
    } catch (e) {
      _ctx.setStatus('Act Structure', 'Error: $e');
      rethrow;
    } finally {
      _ctx.running = false;
      _ctx.notify();
    }
  }

  /// Plan the scenes of sequence [number], replacing any it already has
  /// (and everything written for them).
  Future<void> scenes(StoryProject project, int number) async {
    final sequence = project.sequenceByNumber(number);
    final act = project.actIndexForSequence(number);
    if (sequence == null || act < 0) return;
    _ctx.running = true;
    try {
      final existing = project.sceneIndexesInSequence(number);
      final list = project.scenes[act] ?? const <StoryScene>[];
      var first = existing.isNotEmpty
          ? existing.first
          : list.indexWhere((s) => s.sequence > number);
      if (first == -1) first = list.length;

      final canon = await _agent.canon(project);
      final budget = StoryPacing.forTarget(
        project.targetWords,
      ).scenesFor(number);
      final text = await _agent.run(
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
      await _ctx.repository.saveProject(project);
      _ctx.setStatus(
        'Scenes: Sequence $number',
        '${scenes.length} scenes outlined for "${sequence.title}"!',
      );
    } catch (e) {
      _ctx.setStatus('Scenes: Sequence $number', 'Error: $e');
      rethrow;
    } finally {
      _ctx.running = false;
      _ctx.notify();
    }
  }

  Future<void> beats(StoryProject project, int act, int index) async {
    final scenes = project.scenes[act];
    if (scenes == null || index < 0 || index >= scenes.length) return;
    final scene = scenes[index];
    _ctx.running = true;
    final stage = 'Beats: ${project.sceneLabel(act, index)}';
    try {
      final pacing = StoryPacing.forTarget(project.targetWords);
      final tail = StoryAgent.proseBefore(project, act, index, 0);
      final text = await _agent.run(
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
      await _ctx.repository.saveProject(project);
      _ctx.setStatus(
        stage,
        '"${scene.title}" broken into ${project.beats[key]!.length} beats!',
      );
    } catch (e) {
      _ctx.setStatus(stage, 'Error: $e');
      rethrow;
    } finally {
      _ctx.running = false;
      _ctx.notify();
    }
  }

  /// Studio "generate this act": sequence by sequence, scene by scene —
  /// plan the scenes, then for each scene plan its beats and write it before
  /// moving on, so every later plan can see what was actually written.
  Future<void> fullAct(StoryProject project, int act) async {
    if (act < 0 || act >= project.acts.length) return;
    final actNumber = project.acts[act].number;
    try {
      for (final sequence in project.sequencesInAct(act)) {
        if (project.sceneIndexesInSequence(sequence.number).isEmpty) {
          await scenes(project, sequence.number);
        }
        for (final index in project.sceneIndexesInSequence(sequence.number)) {
          final key = StoryProjectShape.sceneKey(act, index);
          if (project.beats[key]?.isEmpty ?? true) {
            await beats(project, act, index);
          }
          await _prose.writeScene(project, act, index);
        }
        await _memory.sequenceSummary(project, sequence.number);
      }
      _ctx.setStatus('Act $actNumber Complete', 'Ready for review');
    } catch (e) {
      _ctx.setStatus('Error', 'Act $actNumber failed: $e');
      rethrow;
    } finally {
      _ctx.running = false;
      _ctx.notify();
    }
  }
}
