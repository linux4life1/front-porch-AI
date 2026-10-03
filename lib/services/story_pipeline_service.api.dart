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

/// The public pipeline operations. Each is guarded (see [_guard]) and
/// dispatches on the story's engine: the original Quick stages or the Studio
/// ones. Story pages and the web facade call only these.
extension StoryPipelineApi on StoryPipelineService {
  bool _studio(StoryProject p) => p.engineMode == StoryEngineMode.studio;

  /// Stage 0: chat history → event timeline (both engines).
  Future<void> runChatDistiller(StoryProject project) =>
      _guard(() => _chatDistiller(project));

  /// Concept → story bible.
  Future<void> runStoryArchitect(StoryProject project) => _guard(
    () => _studio(project) ? _studioBible(project) : _quickArchitect(project),
  );

  /// Bible → acts (and, in Studio, the eight sequences).
  Future<void> runActStructurer(StoryProject project) => _guard(
    () => _studio(project) ? _studioActs(project) : _quickActs(project),
  );

  /// Act → scenes. In Studio every sequence of the act that has no scenes
  /// yet is planned; sequences already planned are left alone.
  Future<void> runSceneWeaver(StoryProject project, int actIndex) =>
      _guard(() async {
        if (!_studio(project)) return _quickScenes(project, actIndex);
        for (final sequence in project.sequencesInAct(actIndex)) {
          if (project.sceneIndexesInSequence(sequence.number).isEmpty) {
            await _studioScenes(project, sequence.number);
          }
        }
      });

  /// Scene → beats.
  Future<void> runBeatDirector(
    StoryProject project,
    int actIndex,
    int sceneIndex,
  ) => _guard(
    () => _studio(project)
        ? _studioBeats(project, actIndex, sceneIndex)
        : _quickBeats(project, actIndex, sceneIndex),
  );

  /// Write one beat (Quick: draft + edit; Studio: write + continuity check).
  Future<void> runDraftAndEdit(
    StoryProject project,
    int actIndex,
    int sceneIndex,
    int beatIndex,
  ) => _guard(
    () => _studio(project)
        ? _studioWriteBeat(project, actIndex, sceneIndex, beatIndex)
        : _quickDraftAndEdit(project, actIndex, sceneIndex, beatIndex),
  );

  /// Rewrite a beat that already has prose, optionally with an instruction.
  Future<void> rewriteBeat(
    StoryProject project,
    int actIndex,
    int sceneIndex,
    int beatIndex, {
    String directive = '',
  }) => _guard(() async {
    project.prose.remove(
      StoryProjectShape.beatKey(actIndex, sceneIndex, beatIndex),
    );
    if (_studio(project)) {
      await _studioWriteBeat(
        project,
        actIndex,
        sceneIndex,
        beatIndex,
        directive: directive,
      );
    } else {
      await _quickDraftAndEdit(project, actIndex, sceneIndex, beatIndex);
    }
  });

  /// Write every unwritten beat of a scene, then archive it.
  Future<void> autoWriteScene(
    StoryProject project,
    int actIndex,
    int sceneIndex,
  ) => _guard(
    () => _studio(project)
        ? _studioWriteScene(project, actIndex, sceneIndex)
        : _quickAutoWriteScene(project, actIndex, sceneIndex),
  );

  /// Everything for one act: scenes, beats and prose.
  Future<void> generateFullAct(StoryProject project, int actIndex) => _guard(
    () => _studio(project)
        ? _studioFullAct(project, actIndex)
        : _quickFullAct(project, actIndex),
  );

  /// Throw a scene's prose away and write it again.
  Future<void> regenerateSceneProse(
    StoryProject project,
    int actIndex,
    int sceneIndex,
  ) => _guard(() async {
    if (!_studio(project)) {
      return _quickRegenerateScene(project, actIndex, sceneIndex);
    }
    _isRunning = true;
    _setStatus('Rewriting', 'Rewriting scene ${sceneIndex + 1}…');
    try {
      StoryStructure.clearSceneProse(project, actIndex, sceneIndex);
      await _repository.saveProject(project);
      await _studioWriteScene(project, actIndex, sceneIndex);
      _setStatus('Complete', 'Scene rewrite finished!');
    } catch (e) {
      _setStatus('Error', 'Scene rewrite failed: $e');
      rethrow;
    } finally {
      _isRunning = false;
      _notify();
    }
  });

  /// Concept to finished prose without stopping.
  Future<void> runAutopilot(StoryProject project) =>
      _guard(() => _autopilot(project));

  /// "Continue writing": one tap, one scene. The next unfinished scene in
  /// story order gets its beats (if it has none) and its prose; when the
  /// story has run out of planned scenes, the next sequence (Studio) or act
  /// (Quick) is outlined first. Returns false when the story is finished.
  Future<bool> writeNextScene(StoryProject project) async {
    var wrote = false;
    await _guard(() async {
      if (project.acts.isEmpty) {
        await (_studio(project) ? _studioActs(project) : _quickActs(project));
      }
      var next = _nextUnfinished(project);
      if (next == null) {
        if (_studio(project)) {
          final seq = project.sequences
              .where((s) => project.sceneIndexesInSequence(s.number).isEmpty)
              .firstOrNull;
          if (seq != null) await _studioScenes(project, seq.number);
        } else {
          for (var act = 0; act < project.acts.length; act++) {
            if (project.scenes[act]?.isEmpty ?? true) {
              await _quickScenes(project, act);
              break;
            }
          }
        }
        next = _nextUnfinished(project);
      }
      if (next == null) {
        _setStatus('Complete', 'The whole story is written.');
        return;
      }
      final key = StoryProjectShape.sceneKey(next.act, next.index);
      if (project.beats[key]?.isEmpty ?? true) {
        await (_studio(project)
            ? _studioBeats(project, next.act, next.index)
            : _quickBeats(project, next.act, next.index));
      }
      await (_studio(project)
          ? _studioWriteScene(project, next.act, next.index)
          : _quickAutoWriteScene(project, next.act, next.index));
      if (_studio(project)) {
        await _studioSequenceSummary(project, next.scene.sequence);
      }
      wrote = true;
      _setStatus(
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
}
