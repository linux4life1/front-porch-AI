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

/// The Studio stage loop: generate, check the shape in code, have a second
/// model review it, and feed any objection back into a retry.
extension StoryPipelineAgent on StoryPipelineService {
  /// Run one stage to an answer the story can use.
  ///
  /// [prompt] builds the generator prompt; on a retry it receives the last
  /// attempt and what was wrong with it. [validate] is the code-level gate
  /// (returns the problem, or null when the answer is usable). [review]
  /// builds the reviewer prompt; it is skipped when the story has reviews
  /// switched off.
  ///
  /// A reviewer can be wrong, and a story must never dead-end on one: when
  /// every try is rejected by review the last structurally valid answer is
  /// used. Only an answer that never passes [validate] is an error.
  Future<String> _agent(
    StoryProject project, {
    required String stage,
    required String status,
    required String Function(String? previous, String? feedback) prompt,
    String? Function(String output)? validate,
    String Function(String output)? review,
    StoryRole role = StoryRole.planning,
    int maxLength = 8192,
    StoryStageParams params = StoryStageParams.planning,
    int attempts = 3,
    StoryToolSpec? tool,
  }) async {
    String? previous;
    String? feedback;
    String? lastValid;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      _isRunning = true;
      _setStatus(
        stage,
        attempt == 1
            ? status
            : '$status (revising — try $attempt of $attempts)',
      );
      final call = await _call(
        prompt(previous, feedback),
        maxLength: maxLength,
        stage: params,
        project: project,
        role: role,
        label: stage,
        attempt: attempt,
        escalate: attempt > 1 && attempt == attempts,
        tool: tool,
      );
      final output = StoryXml.clean(call.text);
      final problem = validate?.call(output);
      if (problem != null) {
        call.entry
          ..verdict = 'INVALID'
          ..note = problem;
        await _log(project, call.entry);
        previous = output;
        feedback = problem;
        continue;
      }
      lastValid = output;
      if (review == null || !project.reviewEnabled) {
        await _log(project, call.entry);
        return output;
      }

      _setStatus(stage, 'Checking the result…');
      final check = await _call(
        review(output),
        maxLength: 2048,
        project: project,
        role: StoryRole.review,
        label: '$stage review',
        attempt: attempt,
        tool: StoryTools.review,
      );
      final verdict = StoryReview.parse(check.text);
      check.entry
        ..verdict = verdict.pass ? 'PASS' : 'FAIL'
        ..note = verdict.parsed
            ? verdict.feedback
            : 'The review could not be read, so the result was accepted.';
      call.entry.verdict = check.entry.verdict;
      await _log(project, call.entry);
      await _log(project, check.entry);
      if (verdict.pass) return output;
      previous = output;
      feedback = verdict.feedback;
    }
    if (lastValid != null) return lastValid;
    throw StoryStageException.unreadable(stage, attempts);
  }

  /// The chat history a story is built on, as a prompt block body: the
  /// distilled timeline (or raw messages), plus the faithful-retelling rule
  /// when the story asked for one. Empty when the story has no chat basis.
  Future<String> _studioCanon(StoryProject project) async {
    final history = await _getChatHistoryContext(project);
    if (history.trim().isEmpty) return '';
    return project.faithfulMode
        ? '$history\nFAITHFUL RETELLING: this story is a novelization of '
              'these events. Keep them in their original order; do not '
              'replace or invent major events. Deepen and connect them.'
        : history;
  }

  /// The last [words] words of the prose before beat ([act], [scene],
  /// [beat]) — the previous beat, or the end of the previous scene.
  String _proseBefore(
    StoryProject project,
    int act,
    int scene,
    int beat, {
    int words = 220,
  }) {
    String tail(String text) {
      final parts = text.trim().split(RegExp(r'\s+'));
      return parts.length <= words
          ? text.trim()
          : '…${parts.sublist(parts.length - words).join(' ')}';
    }

    for (var b = beat - 1; b >= 0; b--) {
      final text = project.beatText(act, scene, b);
      if (text != null && text.isNotEmpty) return tail(text);
    }
    SceneRef? before;
    for (final ref in project.orderedScenes) {
      if (ref.act == act && ref.index == scene) break;
      before = ref;
    }
    if (before == null) return '';
    final text = project.sceneText(before.act, before.index);
    return text.isEmpty ? '' : tail(text);
  }
}
