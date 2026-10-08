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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/story/story_continuity.dart';

/// Context blocks shared by the Studio prompts. Each returns one tagged
/// block; stages concatenate the ones they need, stable blocks first so a
/// local backend can reuse its prompt cache between calls.
abstract final class StudioContext {
  /// Every Studio stage answers in tags.
  static const tagsOnly =
      'FORMAT: Answer with the tags below and nothing else — no markdown '
      'fences, no commentary before or after. Wrap the whole answer in '
      '<response>…</response>.';

  /// Faithful retellings: planning may connect the chat's events, but not
  /// by bringing in people the chat never had.
  static const noNewPeople =
      'This is a faithful retelling. Every named character must already be '
      'in the cast. Do not introduce new named people; an unnamed passer-by '
      'who does not affect events is the most a scene may add.';

  static String block(String tag, String body) =>
      body.trim().isEmpty ? '' : '<$tag>\n${body.trim()}\n</$tag>';

  static String join(Iterable<String> blocks) =>
      blocks.where((b) => b.trim().isNotEmpty).join('\n\n');

  static String maturity(StoryProject p) => switch (p.maturityRating) {
    'Explicit' =>
      'Unrestricted adult story. Write violence, sexual content, dark themes '
          'and profanity as the story demands, in full, without fading to '
          'black or skipping ahead.',
    'Mature' =>
      'Mature adult story. Realistic violence, strong language and sexual '
          'themes are welcome where they belong; avoid gratuitous detail.',
    _ =>
      'Clean story for all audiences. No graphic violence, sexual content '
          'or strong language.',
  };

  static String preferences(StoryProject p) => block(
    'author_preferences',
    [
      'Point of view: ${p.pov}',
      if (p.selectedGenres.isNotEmpty) 'Genre: ${p.selectedGenres.join(', ')}',
      if (p.selectedMoods.isNotEmpty) 'Mood: ${p.selectedMoods.join(', ')}',
      if (p.writingStyle.isNotEmpty) 'Writing style: ${p.writingStyle}',
      'Narrative pace: ${p.narrativePace}',
      'Dialogue density: ${p.dialogueDensity}',
      'Target length: about ${p.targetWords} words',
      'Format: ${p.storyFormat == StoryFormat.audioDrama ? 'full-cast audio drama' : 'novel'}',
      'Content: ${maturity(p)}',
    ].join('\n'),
  );

  /// The genre contract, tone direction and prose manual from the bible.
  static String style(StoryProject p) => join([
    block('genre_classification', p.style.genreBrief),
    block('tone_and_atmosphere', p.style.toneBrief),
    block(
      'writing_style_description',
      [
        p.style.writingGuide,
        'Point of view: ${p.pov}. Narrative pace: ${p.narrativePace}. '
            'Dialogue density: ${p.dialogueDensity}.',
        'Content: ${maturity(p)}',
      ].where((s) => s.trim().isNotEmpty).join('\n'),
    ),
  ]);

  static String storyInfo(StoryProject p) => block(
    'overall_story_information',
    [
      'Title: ${p.title}',
      'Concept: ${p.concept}',
      if (p.statusQuo.isNotEmpty) 'Status quo: ${p.statusQuo}',
      if (p.incitingIncident.isNotEmpty)
        'Inciting incident: ${p.incitingIncident}',
      if (p.themes.isNotEmpty) 'Thematic argument: ${p.themes}',
      if (p.twists.isNotEmpty) 'Planned reversals: ${p.twists}',
    ].join('\n'),
  );

  static String threads(StoryProject p) => block(
    'narrative_threads',
    p.threads.map((t) => '- ${t.id} — ${t.name}: ${t.description}').join('\n'),
  );

  /// Cast profiles. [only] limits to the people in a scene; [interviewChars]
  /// includes that much of each interview (0 = none) so the writer hears the
  /// voice without the whole dossier.
  static String cast(
    StoryProject p, {
    Iterable<String>? only,
    int interviewChars = 0,
    String tag = 'character_profiles',
  }) {
    final wanted = only
        ?.map((n) => p.castByName(n)?.name)
        .whereType<String>()
        .toSet();
    final members = p.cast.where(
      (c) => wanted == null || wanted.contains(c.name),
    );
    final lines = <String>[];
    for (final c in members) {
      lines.add('### ${c.name} — ${c.role.isEmpty ? 'Supporting' : c.role}');
      if (c.description.isNotEmpty) lines.add(c.description);
      if (c.flaw.isNotEmpty) lines.add('Believes (the lie): ${c.flaw}');
      if (c.desire.isNotEmpty) lines.add('Aches for: ${c.desire}');
      if ((c.voiceSample ?? '').isNotEmpty) {
        lines.add('Voice: ${c.voiceSample}');
      }
      for (final key in const ['appearance', 'goals', 'story_events']) {
        final v = c.details[key]?.trim() ?? '';
        if (v.isNotEmpty) lines.add('${_label(key)}: $v');
      }
      if (interviewChars > 0 && c.interview.isNotEmpty) {
        final excerpt = c.interview.length > interviewChars
            ? '${c.interview.substring(0, interviewChars)}…'
            : c.interview;
        lines.add('In their own words: $excerpt');
      }
      lines.add('');
    }
    return block(tag, lines.join('\n'));
  }

  static String _label(String key) => switch (key) {
    'appearance' => 'Appearance',
    'goals' => 'Current drive',
    'story_events' => 'What has happened to them',
    _ => key,
  };

  static String arcs(StoryProject p) => block(
    'character_arcs',
    [
      for (final c in p.cast)
        if ((c.details['arc'] ?? '').isNotEmpty ||
            (c.details['truth'] ?? '').isNotEmpty)
          '- ${c.name}: lie "${c.flaw}" → truth '
              '"${c.details['truth'] ?? ''}". ${c.details['arc'] ?? ''}',
    ].join('\n'),
  );

  static String relationships(StoryProject p, {Iterable<String>? only}) =>
      block(
        'character_relationships',
        StoryContinuity.relationshipsForPrompt(
          p,
          only ?? p.cast.map((c) => c.name),
        ),
      );

  static String continuity(
    StoryProject p,
    int act,
    int scene, {
    Iterable<String> cast = const [],
  }) => block(
    'continuity_ledger',
    StoryContinuity.forPrompt(p, act, scene, cast: cast),
  );

  static String acts(StoryProject p) => block(
    'act_descriptions',
    p.acts
        .map((a) => '## Act ${a.number}: ${a.title}\n${a.description}')
        .join('\n\n'),
  );

  /// One sequence in full, its neighbours in a line each.
  static String sequences(StoryProject p, int focus) {
    final lines = <String>[];
    for (final s in p.sequences) {
      if (s.number == focus) {
        lines.add(
          '## CURRENT — Sequence ${s.number} (Act ${s.act}): ${s.title}\n'
          'Function: ${s.function}\n'
          'Dramatic question: ${s.dramaticQuestion}\n'
          '${s.description}\n'
          'Climax: ${s.climax}\n'
          'Ending hook: ${s.endingHook}',
        );
      } else {
        lines.add(
          '- Sequence ${s.number} (Act ${s.act}): ${s.title} — '
          '${s.dramaticQuestion}',
        );
      }
    }
    return block('sequence_descriptions', lines.join('\n'));
  }

  /// What has happened before scene ([act], [scene]): earlier sequences by
  /// their condensed summary, the current sequence scene by scene.
  static String storySoFar(StoryProject p, int act, int scene) {
    final scenes = p.scenes[act] ?? const <StoryScene>[];
    final currentSeq = scene < scenes.length
        ? scenes[scene].sequence
        : (scenes.isEmpty ? 0 : scenes.last.sequence);
    final lines = <String>[];
    final summarised = <int>{};
    for (final ref in p.orderedScenes) {
      if (ref.act > act || (ref.act == act && ref.index >= scene)) break;
      final seq = ref.scene.sequence;
      final condensed = p.sequenceByNumber(seq)?.summary ?? '';
      if (seq != currentSeq && condensed.isNotEmpty) {
        if (summarised.add(seq)) lines.add('Sequence $seq: $condensed');
        continue;
      }
      final what = ref.scene.summary.isNotEmpty
          ? ref.scene.summary
          : ref.scene.description;
      lines.add(
        '${p.sceneLabel(ref.act, ref.index)} ${ref.scene.title}: $what',
      );
    }
    return block(
      'story_so_far',
      lines.isEmpty ? 'The story is just beginning.' : lines.join('\n'),
    );
  }

  /// Retry context: the last attempt and what the reviewer wanted changed.
  static String retry(String? previous, String? feedback) {
    if ((feedback ?? '').trim().isEmpty) return '';
    return join([
      if ((previous ?? '').trim().isNotEmpty)
        block('previous_attempt', previous!),
      block('reviewer_feedback', feedback!),
      'Revise the previous attempt so every point in <reviewer_feedback> is '
          'fixed. Keep what already worked. Return the complete answer again '
          'in the same format.',
    ]);
  }
}
