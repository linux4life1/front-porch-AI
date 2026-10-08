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

  /// With [resume], only what an interrupted run left undone is built: the
  /// world and cast and finished interviews are kept.
  Future<void> _studioBible(StoryProject project, {bool resume = false}) async {
    _isRunning = true;
    try {
      final canon = await _studioCanon(project);
      final cards = StoryContext.characterCards(project);

      if (!resume || project.cast.isEmpty) {
        await _studioFoundation(project, canon: canon, cards: cards);
      }

      final leads = project.cast
          .where((c) => c.role.toLowerCase() != 'supporting')
          .take(interviewCap)
          .toList();
      for (final member in leads.isEmpty ? project.cast.take(1) : leads) {
        if (resume && member.interview.trim().isNotEmpty) continue;
        await _interview(project, member);
      }

      await _studioArc(project, canon);
      _setStatus('Story Arc', 'Story bible created!');
    } catch (e) {
      _setStatus('Story Bible', 'Error: $e');
      rethrow;
    } finally {
      _isRunning = false;
      _notify();
    }
  }

  /// The arc step on its own: inciting incident, themes, twists, threads and
  /// character arcs, written together against the world and cast.
  Future<void> _studioArc(StoryProject project, String canon) async {
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
  }

  /// Rewrite the arc and nothing else. The world, cast and interviews stay.
  Future<void> runStoryArc(StoryProject project) => _guard(() async {
    if (!_studio(project) || project.cast.isEmpty) return;
    _isRunning = true;
    try {
      await _studioArc(project, await _studioCanon(project));
      _setStatus('Story Arc', 'Arc rewritten!');
    } catch (e) {
      _setStatus('Story Arc', 'Error: $e');
      rethrow;
    } finally {
      _isRunning = false;
      _notify();
    }
  });

  Future<void> _studioFoundation(
    StoryProject project, {
    required String canon,
    required String cards,
  }) async {
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
  }

  /// Finish a bible whose arc never landed, before anything is planned on
  /// top of it. Acts built without an arc have no threads to carry.
  Future<void> _finishBible(StoryProject project) async {
    if (!StudioParse.arcMissing(project)) return;
    await _studioBible(project, resume: true);
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

  /// The illustrator's brief for a cast member: how they look, in the
  /// story's genre and mood. Same words on desktop and web.
  static String portraitPrompt(StoryProject project, StoryCastMember member) {
    final look = member.details['appearance'] ?? member.description;
    return 'Portrait of ${member.name}. $look. ${project.style.genre} story, '
        '${project.style.mood} mood. Head and shoulders, painterly, no text.';
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
