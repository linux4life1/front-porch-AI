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

/// Studio memory: what a finished scene established, the rolling story so
/// far, and lore search.
extension StoryPipelineStudioMemory on StoryPipelineService {
  /// Read a finished scene for facts, relationship moves and a summary.
  /// Non-fatal: a scene whose archive fails is still a written scene.
  Future<void> _studioArchive(StoryProject project, int act, int index) async {
    final text = project.sceneText(act, index);
    if (text.isEmpty) return;
    final scene = project.scenes[act]![index];
    final stage = 'Archivist: ${project.sceneLabel(act, index)}';
    _isRunning = true;
    _setStatus(stage, 'Noting what "${scene.title}" established…');
    try {
      // A re-archive (after a rewrite or a Director patch) replaces what the
      // scene taught the ledgers rather than stacking on top of it.
      StoryContinuity.forgetScene(project, scene.id);
      final reply = await _callLLM(
        StudioArchivePrompts.archivist(project, act, index, text),
        maxLength: 2048,
        project: project,
        role: StoryRole.review,
        label: stage,
        tool: StoryTools.archive,
      );
      StudioParseProse.applyArchive(project, act, index, StoryXml.clean(reply));
      await _repository.saveProject(project);
      _setStatus(stage, 'World updated!');
    } on StoryStoppedException {
      rethrow;
    } catch (e) {
      debugPrint('[StoryPipeline] Studio archivist failed: $e');
      _setStatus(stage, 'Could not archive this scene: $e');
    } finally {
      _isRunning = false;
      _notify();
    }
  }

  /// Once every scene of a sequence is written, condense it to a paragraph
  /// so later stages carry one line of history instead of a dozen.
  Future<void> _studioSequenceSummary(StoryProject project, int number) async {
    final sequence = project.sequenceByNumber(number);
    final act = project.actIndexForSequence(number);
    if (sequence == null || act < 0 || sequence.summary.isNotEmpty) return;
    final indexes = project.sceneIndexesInSequence(number);
    if (indexes.isEmpty) return;
    final scenes = project.scenes[act]!;
    final done = indexes.every((i) {
      final count =
          project.beats[StoryProjectShape.sceneKey(act, i)]?.length ?? 0;
      return count > 0 && project.beatsWritten(act, i) == count;
    });
    if (!done) return;
    final stage = 'Story so far: Sequence $number';
    _isRunning = true;
    _setStatus(stage, 'Summing up "${sequence.title}"…');
    try {
      final summaries = indexes
          .map((i) {
            final s = scenes[i];
            return '${project.sceneLabel(act, i)} ${s.title}: '
                '${s.summary.isEmpty ? s.description : s.summary}';
          })
          .join('\n');
      final reply = await _callLLM(
        StudioArchivePrompts.sequenceSummary(project, sequence, summaries),
        maxLength: 768,
        project: project,
        role: StoryRole.review,
        label: stage,
        tool: StoryTools.sequenceSummary,
      );
      final cleaned = StoryXml.clean(reply);
      final summary = StoryXml.tag(cleaned, 'story_so_far');
      sequence.summary = summary.isNotEmpty ? summary : StoryXml.strip(cleaned);
      await _repository.saveProject(project);
    } on StoryStoppedException {
      rethrow;
    } catch (e) {
      debugPrint('[StoryPipeline] Sequence summary failed: $e');
    } finally {
      _isRunning = false;
      _notify();
    }
  }

  /// Add an uploaded document to the story's lore, cut into searchable
  /// entries. Re-uploading a file of the same name replaces it.
  Future<int> addLoreDocument(
    StoryProject project,
    String name,
    String text,
  ) async {
    final tag = 'file:$name';
    project.lore.removeWhere((l) => l.relatedTo.contains(tag));
    final entries = StoryLoreIndex.chunkDocument(name, text);
    project.lore.addAll(entries);
    await _repository.saveProject(project);
    _notify();
    return entries.length;
  }

  /// What the writer would be shown for [query] at scene ([act], [index]).
  Future<List<LoreHit>> searchLore(
    StoryProject project,
    String query, {
    int? act,
    int? index,
  }) => _loreIndex.search(
    query,
    act == null || index == null
        ? project.lore
        : StoryLoreIndex.knownAt(project, act, index),
    limit: 6,
  );

  /// Whether lore search is using the embedding model (true) or plain word
  /// overlap (false).
  bool get loreSearchIsSemantic => _loreIndex.semantic;
}
