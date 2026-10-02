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

/// Studio bible: world and cast, character interviews, then the story arc.
extension StoryPipelineStudioBible on StoryPipelineService {
  /// Interviews are a call each, so only the people who carry the story get
  /// one up front; anyone else can be interviewed from the Cast screen.
  static const interviewCap = 6;

  Future<void> _studioBible(StoryProject project) async {
    _isRunning = true;
    try {
      final canon = await _studioCanon(project);
      final cards = StoryContext.characterCards(project);

      final foundation = await _agent(
        project,
        stage: 'World & Cast',
        status: 'Building the world and the people in it…',
        params: StoryStageParams.bible,
        validate: StudioParse.checkFoundation,
        prompt: (previous, feedback) => StudioBiblePrompts.foundation(
          project,
          cards: cards,
          canon: canon,
          previous: previous,
          feedback: feedback,
        ),
      );
      StudioParse.applyFoundation(project, foundation);
      await _repository.saveProject(project);

      final leads = project.cast
          .where((c) => c.role.toLowerCase() != 'supporting')
          .take(interviewCap)
          .toList();
      for (final member in leads.isEmpty ? project.cast.take(1) : leads) {
        await _interview(project, member);
      }

      final arc = await _agent(
        project,
        stage: 'Story Arc',
        status: 'Finding what breaks this world, and what the story argues…',
        params: StoryStageParams.bible,
        validate: StudioParse.checkArc,
        prompt: (previous, feedback) => StudioBiblePrompts.arc(
          project,
          canon: canon,
          previous: previous,
          feedback: feedback,
        ),
        review: (output) => StudioBiblePrompts.arcReview(project, output),
      );
      StudioParse.applyArc(project, arc);
      await _repository.saveProject(project);
      _setStatus('Story Arc', 'Story bible created!');
    } catch (e) {
      _setStatus('Story Bible', 'Error: $e');
      rethrow;
    } finally {
      _isRunning = false;
      _notify();
    }
  }

  Future<void> _interview(StoryProject project, StoryCastMember member) async {
    final text = await _agent(
      project,
      stage: 'Interview: ${member.name}',
      status: 'Letting ${member.name} talk…',
      role: StoryRole.prose,
      params: StoryStageParams.prose,
      maxLength: 4096,
      attempts: 2,
      validate: StudioParse.checkInterview,
      prompt: (previous, feedback) => StudioBiblePrompts.interview(
        project,
        member,
        previous: previous,
        feedback: feedback,
      ),
    );
    StudioParse.applyInterview(member, text);
    await _repository.saveProject(project);
  }

  /// Interview (or re-interview) one cast member on request.
  Future<void> runCharacterInterview(StoryProject project, String name) =>
      _guard(() async {
        final member = project.castByName(name);
        if (member == null) return;
        _isRunning = true;
        try {
          await _interview(project, member);
          _setStatus('Interview: ${member.name}', 'Interview finished!');
        } catch (e) {
          _setStatus('Interview: ${member.name}', 'Error: $e');
          rethrow;
        } finally {
          _isRunning = false;
          _notify();
        }
      });
}
