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

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/story/story.dart';
import 'package:front_porch_ai/services/story_pipeline/story_pipeline.dart';

/// The public pipeline operations. Each is guarded (see [guard]) and
/// dispatches on the story's engine: the original Quick stages or the Studio
/// ones. Builds and owns every stage collaborator.
class StoryPipelineRunner {
  StoryPipelineRunner(this._ctx) {
    llm = StoryLlmCaller(_ctx);
    history = StoryChatHistory(_ctx);
    agent = StoryAgent(_ctx, llm, history);
    distiller = StoryChatDistiller(_ctx, llm, history);
    quickPlanning = StoryQuickPlanning(_ctx, llm, history);
    quickProse = StoryQuickProse(_ctx, llm);
    quickActs = StoryQuickActs(_ctx, llm, quickPlanning);
    memory = StoryStudioMemory(_ctx, llm);
    bible = StoryPipelineStudioBible(_ctx, agent);
    studioProse = StoryStudioProse(_ctx, llm, agent, memory);
    structure = StoryStudioStructure(_ctx, agent, studioProse, memory);
    director = StoryDirectorPlanner(_ctx, llm, agent);
    directorApply = StoryDirectorApplier(_ctx, llm, studioProse, memory);
  }

  final StoryPipelineContext _ctx;
  late final StoryLlmCaller llm;
  late final StoryChatHistory history;
  late final StoryAgent agent;
  late final StoryChatDistiller distiller;
  late final StoryQuickPlanning quickPlanning;
  late final StoryQuickProse quickProse;
  late final StoryQuickActs quickActs;
  late final StoryStudioMemory memory;
  late final StoryPipelineStudioBible bible;
  late final StoryStudioProse studioProse;
  late final StoryStudioStructure structure;
  late final StoryDirectorPlanner director;
  late final StoryDirectorApplier directorApply;

  /// Ask the running operation to stop at the next safe point. Everything
  /// already written stays saved.
  void requestStop() {
    if (!_ctx.isRunning || _ctx.stopRequested) return;
    _ctx.stopRequested = true;
    _ctx.statusMessage = 'Stopping…';
    _ctx.llmService.abortGeneration();
    _ctx.lanes?.worker()?.abortGeneration();
    _ctx.notify();
  }

  /// Wraps every public operation. Tracks nesting so `isRunning` and the stop
  /// request span the outermost call, and turns a user stop into a quiet
  /// finish instead of an error.
  Future<void> guard(Future<void> Function() body) async {
    _ctx.depth++;
    try {
      await body();
    } on StoryStoppedException {
      if (_ctx.depth > 1) rethrow;
      _ctx.currentStep = 'Stopped';
      _ctx.statusMessage = 'Stopped. Everything written so far is saved.';
    } finally {
      _ctx.depth--;
      if (_ctx.depth == 0) {
        _ctx.running = false;
        _ctx.stopRequested = false;
        _ctx.notify();
        // Put the chat model back after the run, not after every call, so
        // a run that alternates lanes swaps once per stage.
        unawaited(
          llm.restoreLaneHosts().catchError(
            (Object e) => debugPrint('[Story] lane restore failed: $e'),
          ),
        );
      }
    }
  }

  bool _studio(StoryProject p) => p.engineMode == StoryEngineMode.studio;

  /// Stage 0: chat history → event timeline (both engines).
  Future<void> runChatDistiller(StoryProject project) =>
      guard(() => distiller.run(project));

  /// Concept → story bible.
  Future<void> runStoryArchitect(StoryProject project) => guard(
    () => _studio(project)
        ? bible.bible(project)
        : quickPlanning.architect(project),
  );

  /// Bible → acts (and, in Studio, the eight sequences).
  Future<void> runActStructurer(StoryProject project) => guard(() async {
    if (!_studio(project)) return quickPlanning.acts(project);
    await bible.finishBible(project);
    await structure.acts(project);
  });

  /// Act → scenes. In Studio every sequence of the act that has no scenes
  /// yet is planned; sequences already planned are left alone.
  Future<void> runSceneWeaver(StoryProject project, int actIndex) =>
      guard(() async {
        if (!_studio(project)) return quickPlanning.scenes(project, actIndex);
        for (final sequence in project.sequencesInAct(actIndex)) {
          if (project.sceneIndexesInSequence(sequence.number).isEmpty) {
            await structure.scenes(project, sequence.number);
          }
        }
      });

  /// Scene → beats.
  Future<void> runBeatDirector(
    StoryProject project,
    int actIndex,
    int sceneIndex,
  ) => guard(
    () => _studio(project)
        ? structure.beats(project, actIndex, sceneIndex)
        : quickPlanning.beats(project, actIndex, sceneIndex),
  );

  /// Write one beat (Quick: draft + edit; Studio: write + continuity check).
  Future<void> runDraftAndEdit(
    StoryProject project,
    int actIndex,
    int sceneIndex,
    int beatIndex,
  ) => guard(
    () => _studio(project)
        ? studioProse.writeBeat(project, actIndex, sceneIndex, beatIndex)
        : quickProse.draftAndEdit(project, actIndex, sceneIndex, beatIndex),
  );

  /// Rewrite a beat that already has prose, optionally with an instruction.
  Future<void> rewriteBeat(
    StoryProject project,
    int actIndex,
    int sceneIndex,
    int beatIndex, {
    String directive = '',
  }) => guard(() async {
    project.prose.remove(
      StoryProjectShape.beatKey(actIndex, sceneIndex, beatIndex),
    );
    if (_studio(project)) {
      await studioProse.writeBeat(
        project,
        actIndex,
        sceneIndex,
        beatIndex,
        directive: directive,
      );
    } else {
      await quickProse.draftAndEdit(project, actIndex, sceneIndex, beatIndex);
    }
  });

  /// Write every unwritten beat of a scene, then archive it.
  Future<void> autoWriteScene(
    StoryProject project,
    int actIndex,
    int sceneIndex,
  ) => guard(
    () => _studio(project)
        ? studioProse.writeScene(project, actIndex, sceneIndex)
        : quickProse.autoWriteScene(project, actIndex, sceneIndex),
  );

  /// Everything for one act: scenes, beats and prose.
  Future<void> generateFullAct(StoryProject project, int actIndex) => guard(
    () => _studio(project)
        ? structure.fullAct(project, actIndex)
        : quickActs.fullAct(project, actIndex),
  );

  /// Throw a scene's prose away and write it again.
  Future<void> regenerateSceneProse(
    StoryProject project,
    int actIndex,
    int sceneIndex,
  ) => guard(() async {
    if (!_studio(project)) {
      return quickActs.regenerateScene(project, actIndex, sceneIndex);
    }
    _ctx.running = true;
    _ctx.setStatus('Rewriting', 'Rewriting scene ${sceneIndex + 1}…');
    try {
      StoryStructure.clearSceneProse(project, actIndex, sceneIndex);
      await _ctx.repository.saveProject(project);
      await studioProse.writeScene(project, actIndex, sceneIndex);
      _ctx.setStatus('Complete', 'Scene rewrite finished!');
    } catch (e) {
      _ctx.setStatus('Error', 'Scene rewrite failed: $e');
      rethrow;
    } finally {
      _ctx.running = false;
      _ctx.notify();
    }
  });

  /// Concept to finished prose without stopping.
  Future<void> runAutopilot(StoryProject project) =>
      guard(() => _autopilot(project));

  /// Rewrite the arc and nothing else. The world, cast and interviews stay.
  Future<void> runStoryArc(StoryProject project) => guard(() async {
    if (!_studio(project) || project.cast.isEmpty) return;
    await bible.rewriteArc(project);
  });

  /// Interview (or re-interview) one cast member on request.
  Future<void> runCharacterInterview(StoryProject project, String name) =>
      guard(() => bible.characterInterview(project, name));

  /// Plan (or re-plan) the scenes of one sequence on request.
  Future<void> planSequenceScenes(StoryProject project, int number) =>
      guard(() => structure.scenes(project, number));

  /// Propose a Director plan for [directive]; see
  /// [StoryDirectorPlanner.plan].
  Future<void> runDirectorPlan(
    StoryProject project,
    String directive, {
    required bool protectWrittenProse,
    String refinement = '',
  }) => guard(
    () => director.plan(
      project,
      directive,
      protectWrittenProse: protectWrittenProse,
      refinement: refinement,
    ),
  );

  /// Apply the ticked actions of the current Director plan.
  Future<void> applyDirectorPlan(StoryProject project) =>
      guard(() => directorApply.apply(project));

  /// "Continue writing": one tap, one scene. The next unfinished scene in
  /// story order gets its beats (if it has none) and its prose; when the
  /// story has run out of planned scenes, the next sequence (Studio) or act
  /// (Quick) is outlined first. Returns false when the story is finished.
  Future<bool> writeNextScene(StoryProject project) async {
    var wrote = false;
    await guard(() async {
      if (project.acts.isEmpty) {
        await (_studio(project)
            ? structure.acts(project)
            : quickPlanning.acts(project));
      }
      if (_studio(project)) await memory.archiveMissed(project);
      var next = _nextUnfinished(project);
      if (next == null) {
        if (_studio(project)) {
          final seq = project.sequences
              .where((s) => project.sceneIndexesInSequence(s.number).isEmpty)
              .firstOrNull;
          if (seq != null) await structure.scenes(project, seq.number);
        } else {
          for (var act = 0; act < project.acts.length; act++) {
            if (project.scenes[act]?.isEmpty ?? true) {
              await quickPlanning.scenes(project, act);
              break;
            }
          }
        }
        next = _nextUnfinished(project);
      }
      if (next == null) {
        _ctx.setStatus('Complete', 'The whole story is written.');
        return;
      }
      final key = StoryProjectShape.sceneKey(next.act, next.index);
      if (project.beats[key]?.isEmpty ?? true) {
        await (_studio(project)
            ? structure.beats(project, next.act, next.index)
            : quickPlanning.beats(project, next.act, next.index));
      }
      await (_studio(project)
          ? studioProse.writeScene(project, next.act, next.index)
          : quickProse.autoWriteScene(project, next.act, next.index));
      if (_studio(project)) {
        await memory.sequenceSummary(project, next.scene.sequence);
      }
      wrote = true;
      _ctx.setStatus(
        'Scene ${project.sceneLabel(next.act, next.index)}',
        '"${next.scene.title}" is written.',
      );
    });
    return wrote;
  }

  SceneRef? _nextUnfinished(StoryProject project) {
    for (final ref in project.orderedScenes) {
      final count =
          project
              .beats[StoryProjectShape.sceneKey(ref.act, ref.index)]
              ?.length ??
          0;
      if (count == 0 || project.beatsWritten(ref.act, ref.index) < count) {
        return ref;
      }
    }
    return null;
  }

  /// Autopilot: run the entire pipeline from concept to finished prose.
  Future<void> _autopilot(StoryProject project) async {
    try {
      // Writes what is left. The bible and the acts are built only when
      // they do not exist yet; a fresh start is "Regenerate bible" first.
      if (project.cast.isEmpty && project.concept.trim().isNotEmpty) {
        await runStoryArchitect(project);
      }
      if (project.acts.isEmpty) {
        await runActStructurer(project);
      } else if (_studio(project)) {
        await bible.finishBible(project);
      }
      // One scene at a time through the same path as "Continue writing",
      // so Stop lands between scenes and nothing written is touched.
      while (await writeNextScene(project)) {
        if (_ctx.stopRequested) break;
      }

      _ctx.setStatus('Complete', 'Story generation finished!');
    } catch (e) {
      _ctx.setStatus('Error', 'Pipeline failed: $e');
      rethrow;
    }
  }
}
