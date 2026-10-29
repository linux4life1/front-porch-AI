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
import 'package:front_porch_ai/services/story_stage_params.dart';

/// Studio bible: world and cast, character interviews, then the story arc.
class StoryPipelineStudioBible {
  StoryPipelineStudioBible(this._ctx, this._agent);

  final StoryPipelineContext _ctx;
  final StoryAgent _agent;

  /// Interviews are a call each, so only the people who carry the story get
  /// one up front; anyone else can be interviewed from the Cast screen.
  static const interviewCap = 6;

  /// With [resume], only what an interrupted run left undone is built: the
  /// world and cast and finished interviews are kept.
  Future<void> bible(StoryProject project, {bool resume = false}) async {
    _ctx.running = true;
    try {
      final canon = await _agent.canon(project);
      final cards = StoryContext.characterCards(project);

      if (!resume || project.cast.isEmpty) {
        // The world's book is copied in before the model writes a word, so
        // the foundation appends to it instead of inventing the world again.
        final world = _ctx.worldFor(project);
        StoryWorldContext.copyLore(project, world);
        await _foundation(
          project,
          canon: canon,
          cards: cards,
          world: StoryWorldContext.settingWorld(world),
        );
      }

      final leads = project.cast
          .where((c) => c.role.toLowerCase() != 'supporting')
          .take(interviewCap)
          .toList();
      for (final member in leads.isEmpty ? project.cast.take(1) : leads) {
        if (resume && member.interview.trim().isNotEmpty) continue;
        await _interview(project, member);
      }

      await _arc(project, canon);
      _ctx.setStatus('Story Arc', 'Story bible created!');
    } catch (e) {
      _ctx.setStatus('Story Bible', 'Error: $e');
      rethrow;
    } finally {
      _ctx.running = false;
      _ctx.notify();
    }
  }

  /// The arc step on its own: inciting incident, themes, twists, threads and
  /// character arcs, written together against the world and cast.
  Future<void> _arc(StoryProject project, String canon) async {
    final arc = await _agent.run(
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
    await _ctx.repository.saveProject(project);
  }

  /// Rewrite the arc and nothing else. The world, cast and interviews stay.
  /// The caller has already checked the story is Studio with a cast.
  Future<void> rewriteArc(StoryProject project) async {
    _ctx.running = true;
    try {
      await _arc(project, await _agent.canon(project));
      _ctx.setStatus('Story Arc', 'Arc rewritten!');
    } catch (e) {
      _ctx.setStatus('Story Arc', 'Error: $e');
      rethrow;
    } finally {
      _ctx.running = false;
      _ctx.notify();
    }
  }

  Future<void> _foundation(
    StoryProject project, {
    required String canon,
    required String cards,
    String world = '',
  }) async {
    final foundation = await _agent.run(
      project,
      stage: 'World & Cast',
      status: 'Building the world and the people in it…',
      params: StoryStageParams.bible,
      validate: StudioParse.checkFoundation,
      prompt: (previous, feedback) => StudioBiblePrompts.foundation(
        project,
        cards: cards,
        canon: canon,
        world: world,
        previous: previous,
        feedback: feedback,
      ),
    );
    StudioParse.applyFoundation(project, foundation);
    await _ctx.repository.saveProject(project);
  }

  /// Finish a bible whose arc never landed, before anything is planned on
  /// top of it. Acts built without an arc have no threads to carry.
  Future<void> finishBible(StoryProject project) async {
    if (!StudioParse.arcMissing(project)) return;
    await bible(project, resume: true);
  }

  Future<void> _interview(StoryProject project, StoryCastMember member) async {
    final text = await _agent.run(
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
    await _ctx.repository.saveProject(project);
  }

  /// The illustrator's brief for a cast member: how they look, in the
  /// story's genre and mood. Same words on desktop and web.
  static String portraitPrompt(StoryProject project, StoryCastMember member) {
    final look = member.details['appearance'] ?? member.description;
    return 'Portrait of ${member.name}. $look. ${project.style.genre} story, '
        '${project.style.mood} mood. Head and shoulders, painterly, no text.';
  }

  /// Interview (or re-interview) one cast member on request.
  Future<void> characterInterview(StoryProject project, String name) async {
    final member = project.castByName(name);
    if (member == null) return;
    _ctx.running = true;
    try {
      await _interview(project, member);
      _ctx.setStatus('Interview: ${member.name}', 'Interview finished!');
    } catch (e) {
      _ctx.setStatus('Interview: ${member.name}', 'Error: $e');
      rethrow;
    } finally {
      _ctx.running = false;
      _ctx.notify();
    }
  }
}
