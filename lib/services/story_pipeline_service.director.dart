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

/// The Director: plan a change, let the user tick what they want, apply it,
/// undo it. Planning and review live here; applying is the next part.
extension StoryPipelineDirector on StoryPipelineService {
  /// Propose a plan for [directive]. With [refinement], the current plan is
  /// revised instead of replaced. Nothing changes until [applyDirectorPlan].
  Future<void> runDirectorPlan(
    StoryProject project,
    String directive, {
    required bool protectWrittenProse,
    String refinement = '',
  }) => _guard(() async {
    final request = directive.trim();
    if (request.isEmpty) return;
    _isRunning = true;
    try {
      final previousPlan = refinement.trim().isEmpty
          ? null
          : project.directorPlan;
      final text = await _agent(
        project,
        stage: 'Director',
        status: refinement.trim().isEmpty
            ? 'Planning the change…'
            : 'Revising the plan…',
        validate: StoryDirector.check,
        prompt: (previous, feedback) => DirectorPrompts.planner(
          project,
          directive: request,
          protect: protectWrittenProse,
          previousPlan: previousPlan,
          refinement: refinement,
          previous: previous,
          feedback: feedback,
        ),
      );
      final plan = StoryDirector.parsePlan(project, text, directive: request);
      if (plan.actions.isEmpty) {
        throw StoryStageException(
          'The Director could not turn that request into changes it knows '
          'how to make. Try saying which scenes or characters it is about.',
        );
      }
      StoryDirector.applyProtection(project, plan, protectWrittenProse);
      project.directorPlan = plan;
      await _repository.saveProject(project);

      if (project.reviewEnabled) {
        _setStatus('Director', 'Checking the plan for contradictions…');
        final check = await _call(
          DirectorPrompts.review(project, plan),
          maxLength: 1536,
          project: project,
          role: StoryRole.review,
          label: 'Director review',
        );
        final verdict = StoryReview.parse(check.text);
        check.entry
          ..verdict = verdict.pass ? 'PASS' : 'FAIL'
          ..note = verdict.feedback;
        await _log(project, check.entry);
        plan.review = verdict.pass
            ? 'consistent'
            : (verdict.problems.isNotEmpty
                  ? verdict.problems.join(' ')
                  : verdict.critique);
        await _repository.saveProject(project);
      }
      _setStatus(
        'Director',
        '${plan.actions.length} change${plan.actions.length == 1 ? '' : 's'} '
            'proposed. Tick the ones you want, then apply.',
      );
    } catch (e) {
      _setStatus('Director', 'Error: $e');
      rethrow;
    } finally {
      _isRunning = false;
      _notify();
    }
  });

  /// Re-evaluate the locks after the user flips "Protect written prose".
  Future<void> setDirectorProtection(StoryProject project, bool protect) async {
    final plan = project.directorPlan;
    if (plan == null) return;
    StoryDirector.applyProtection(project, plan, protect);
    await _repository.saveProject(project);
    _notify();
  }

  Future<void> setDirectorActionEnabled(
    StoryProject project,
    int index,
    bool enabled,
  ) async {
    final plan = project.directorPlan;
    if (plan == null || index < 0 || index >= plan.actions.length) return;
    plan.actions[index].enabled = enabled;
    await _repository.saveProject(project);
    _notify();
  }

  Future<void> discardDirectorPlan(StoryProject project) async {
    if (project.directorPlan == null) return;
    project.directorPlan = null;
    await _repository.saveProject(project);
    _notify();
  }

  /// Put the story back as it was before the last applied plan.
  Future<bool> undoDirectorPlan(StoryProject project) async {
    final id = project.dbId;
    if (id == null) return false;
    final json = await store.readUndo(id);
    if (json == null) return false;
    final restored = StoryProject.fromJsonString(json)..dbId = id;
    restored.directorApplied = null;
    await _repository.replaceProject(restored);
    await store.clearUndo(id);
    _setStatus('Director', 'Undone. The story is back as it was.');
    _notify();
    return true;
  }
}
