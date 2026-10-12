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

/// The Director: plan a change, let the user tick what they want, undo it.
/// Applying a plan is [StoryDirectorApplier].
class StoryDirectorPlanner {
  StoryDirectorPlanner(this._ctx, this._llm, this._agent);

  final StoryPipelineContext _ctx;
  final StoryLlmCaller _llm;
  final StoryAgent _agent;

  /// Propose a plan for [directive]. With [refinement], the current plan is
  /// revised instead of replaced. Nothing changes until [StoryDirectorApplier.apply].
  Future<void> plan(
    StoryProject project,
    String directive, {
    required bool protectWrittenProse,
    String refinement = '',
  }) async {
    final request = directive.trim();
    if (request.isEmpty) return;
    _ctx.running = true;
    try {
      final previousPlan = refinement.trim().isEmpty
          ? null
          : project.directorPlan;
      final text = await _agent.run(
        project,
        stage: 'Director',
        tool: StoryTools.director,
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
      await _ctx.repository.saveProject(project);

      if (project.reviewEnabled) {
        _ctx.setStatus('Director', 'Checking the plan for contradictions…');
        final check = await _llm.invoke(
          DirectorPrompts.review(project, plan),
          maxLength: 1536,
          project: project,
          role: StoryRole.review,
          label: 'Director review',
          tool: StoryTools.review,
        );
        final verdict = StoryReview.parse(check.text);
        check.entry
          ..verdict = verdict.pass ? 'PASS' : 'FAIL'
          ..note = verdict.feedback;
        await _llm.log(project, check.entry);
        plan.review = verdict.pass
            ? 'consistent'
            : (verdict.problems.isNotEmpty
                  ? verdict.problems.join(' ')
                  : verdict.critique);
        await _ctx.repository.saveProject(project);
      }
      _ctx.setStatus(
        'Director',
        '${plan.actions.length} change${plan.actions.length == 1 ? '' : 's'} '
            'proposed. Tick the ones you want, then apply.',
      );
    } catch (e) {
      _ctx.setStatus('Director', 'Error: $e');
      rethrow;
    } finally {
      _ctx.running = false;
      _ctx.notify();
    }
  }

  /// Re-evaluate the locks after the user flips "Protect written prose".
  Future<void> setProtection(StoryProject project, bool protect) async {
    final plan = project.directorPlan;
    if (plan == null) return;
    StoryDirector.applyProtection(project, plan, protect);
    await _ctx.repository.saveProject(project);
    _ctx.notify();
  }

  Future<void> setActionEnabled(
    StoryProject project,
    int index,
    bool enabled,
  ) async {
    final plan = project.directorPlan;
    if (plan == null || index < 0 || index >= plan.actions.length) return;
    plan.actions[index].enabled = enabled;
    await _ctx.repository.saveProject(project);
    _ctx.notify();
  }

  Future<void> discard(StoryProject project) async {
    if (project.directorPlan == null) return;
    project.directorPlan = null;
    await _ctx.repository.saveProject(project);
    _ctx.notify();
  }

  /// Put the story back as it was before the last applied plan.
  Future<bool> undo(StoryProject project) async {
    final id = project.dbId;
    if (id == null) return false;
    final json = await _ctx.store.readUndo(id);
    if (json == null) return false;
    final restored = StoryProject.fromJsonString(json)..dbId = id;
    restored.directorApplied = null;
    await _ctx.repository.replaceProject(restored);
    await _ctx.store.clearUndo(id);
    _ctx.setStatus('Director', 'Undone. The story is back as it was.');
    _ctx.notify();
    return true;
  }
}
