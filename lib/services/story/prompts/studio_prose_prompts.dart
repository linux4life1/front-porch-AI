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
import 'package:front_porch_ai/services/story/prompts/studio_bible_prompts.dart';
import 'package:front_porch_ai/services/story/prompts/studio_context.dart';
import 'package:front_porch_ai/services/story/story_lenses.dart';
import 'package:front_porch_ai/services/story/story_pacing.dart';

/// Studio beat planning, prose writing, the continuity check and its
/// surgical fix. Staging and theory adapted from EllipsisProse (Apache-2.0,
/// see NOTICE); `*Role` constants are stable opening lines the E2E backend
/// routes on.
abstract final class StudioProsePrompts {
  static bool _small(StoryProject p) => p.promptTier == PromptTier.smallLocal;

  static const beatTypes = [
    'Environment',
    'Reflection',
    'Memory',
    'Action',
    'Sensory',
    'Dialogue',
    'Transition',
  ];

  /// The scene as the planner wrote it, for every later stage.
  static String sceneBlueprint(StoryProject p, int act, int index) {
    final s = p.scenes[act]![index];
    return StudioContext.block(
      'scene_blueprint',
      [
        'Scene ${p.sceneLabel(act, index)}: ${s.title}',
        if (s.sceneType.isNotEmpty) 'Type: ${s.sceneType.toUpperCase()}',
        if (s.pov.isNotEmpty) 'Point-of-view character: ${s.pov}',
        'Characters present: ${s.castNames.join(', ')}',
        'Setting: ${s.location}',
        if (s.objective.isNotEmpty) 'Objective: ${s.objective}',
        'What happens: ${s.description}',
        if (s.valueFrom.isNotEmpty || s.valueTo.isNotEmpty)
          'Value shift: ${s.valueFrom} → ${s.valueTo}',
        if (s.commitments.isNotEmpty && s.commitments.toLowerCase() != 'none')
          'Plot commitments (deliver these exactly): ${s.commitments}',
        if (s.entry.isNotEmpty) 'Opens: ${s.entry}',
        if (s.exit.isNotEmpty) 'Closes: ${s.exit}',
      ].join('\n'),
    );
  }

  static String beatList(List<StoryBeat> beats) => StudioContext.block(
    'beat_choreography',
    [
      for (final b in beats)
        'Beat ${b.number} [${b.type}] '
            '${b.initiator.isEmpty ? '' : '${b.initiator}'
                      '${b.reactor.isEmpty || b.reactor == '—' ? '' : ' → ${b.reactor}'}: '}'
            '${b.description}'
            '${b.subtext.isEmpty ? '' : ' Unspoken: ${b.subtext}'}'
            '${b.anchor.isEmpty || b.anchor == '—' ? '' : ' ANCHOR: ${b.anchor}'}',
    ].join('\n'),
  );

  // ── Beat planner ───────────────────────────────────────────────────────

  static const beatsRole =
      'You are an author choreographing one scene of your novel into beats.';

  static String beats(
    StoryProject p,
    int act,
    int index, {
    String previousTail = '',
    String? previous,
    String? feedback,
  }) {
    final scene = p.scenes[act]![index];
    final pacing = StoryPacing.forTarget(p.targetWords);
    final lens = StoryLenses.resolve(p, scene.lens);
    final scenes = p.scenes[act]!;
    final next = index + 1 < scenes.length ? scenes[index + 1] : null;
    final rules = [
      'Write ${pacing.beatsMin} to ${pacing.beatsMax} beats. Each beat is one '
          'dramatic movement that will become about '
          '${StoryPacing.wordsPerBeat} words of prose.',
      'Beat 1 opens exactly at the scene\'s entrance conditions; the last '
          'beat lands its exit conditions. Never run into the next scene.',
      'Do not draw a straight line from start to finish. Invent the small '
          'events in between: a deflection, a discovery, a pause that says '
          'too much, a shift in who holds the room.',
      if (p.faithfulMode) StudioContext.noNewPeople,
      'Beats are linked by cause ("therefore", "but"), never just sequence. '
          'A new beat starts when someone changes tactic.',
      'Say who does what to whom. Each beat names its initiator, the reactor '
          '(or — when someone acts alone), the action, and the reaction in '
          'human order: flinch, then movement, then speech.',
      'If a camera could not film it, it is not the centre of a beat. '
          'Feeling shows as action, movement or speech. A memory must be '
          'triggered by something physically present and stay brief.',
      'Use the space: distance between people, the objects in the room, the '
          'weather. No talking heads.',
      'People talk in most beats when more than one is present, not only in '
          'beats typed Dialogue. Talk is a move: to reassure, warn, deflect, '
          'get closer, win.',
      'Vary beat types (${beatTypes.join(', ')}); never three of one type '
          'in a row.',
      'Write a specification, not a draft: what happens and why it matters. '
          'Leave the wording to the prose writer.',
      'ANCHOR: the one irreversible fact, decision or reveal the beat '
          'establishes, in one concrete sentence (— for a pure transition). '
          'Every plot commitment of the scene must be some beat\'s anchor.',
    ];
    return StudioContext.join([
      beatsRole,
      StudioContext.block('beat_rules', rules.map((r) => '- $r').join('\n')),
      StudioContext.style(p),
      if (p.lensesEnabled)
        StudioContext.block('writing_lens', '${lens.name}: ${lens.prompt}'),
      StudioContext.cast(
        p,
        only: scene.castNames,
        interviewChars: _small(p) ? 0 : 500,
      ),
      StudioContext.relationships(p, only: scene.castNames),
      StudioContext.storySoFar(p, act, index),
      StudioContext.continuity(p, act, index, cast: scene.castNames),
      StudioContext.block('previous_scene_ending', previousTail),
      sceneBlueprint(p, act, index),
      if (next != null)
        StudioContext.block(
          'next_scene_opening',
          '${next.title}: ${next.entry.isEmpty ? next.description : next.entry}',
        ),
      StudioContext.retry(previous, feedback),
      StudioContext.tagsOnly,
      '''<response>
  <beats>
    <beat>
      <beat_type>${beatTypes.join(' | ')}</beat_type>
      <initiator>Who acts</initiator>
      <reactor>Who answers, or —</reactor>
      <action>One or two sentences: the concrete thing done or said.</action>
      <reaction>How the other person takes it (or — when alone).</reaction>
      <tactic>The move underneath: provokes, evades, pleads, defuses with a joke…</tactic>
      <subtext>What is not being said.</subtext>
      <anchor>The irreversible fact, decision or reveal — or —.</anchor>
    </beat>
  </beats>
</response>''',
    ]);
  }

  static const beatsReviewRole =
      'You are a continuity and pacing editor checking the beats of one '
      'scene.';

  static String beatsReview(
    StoryProject p,
    int act,
    int index,
    String generated,
  ) {
    final pacing = StoryPacing.forTarget(p.targetWords);
    return StudioContext.join([
      beatsReviewRole,
      StudioContext.block(
        'review_criteria',
        '''
1. Count: ${pacing.beatsMin} to ${pacing.beatsMax} beats?
2. Does each beat move things on, or do some repeat the same exchange or posture?
3. Does beat 1 open at the entrance conditions and the last beat land the exit conditions, without running into the next scene?
4. Is every plot commitment of the scene some beat's anchor, in exact terms?
5. Is it clear who does what in every beat? Does anyone appear, vanish or hold something they could not have?
6. Is there variety of beat types, and do people talk when more than one is present?

PASS when the beats are sound; note small suggestions without failing. FAIL only for a wrong count, a dropped plot commitment, beats that loop, a boundary overrun or a continuity break.''',
      ),
      StudioContext.continuity(
        p,
        act,
        index,
        cast: p.scenes[act]![index].castNames,
      ),
      sceneBlueprint(p, act, index),
      StudioContext.block('generated_beats', generated),
      StudioBiblePrompts.reviewFormat,
    ]);
  }

  // ── Writer ─────────────────────────────────────────────────────────────

  static const writerRole =
      'You are a prize-winning prose stylist with an invisible hand, musical '
      'sentences and a gift for putting the reader inside a body in a place.';

  static const audioRole =
      'You are an audio-drama scriptwriter and director writing a full-cast, '
      'narrator-led production.';

  static const _proseRules = [
    'Write only the beat marked CURRENT. Earlier beats are already written; '
        'later beats are not yours. Deliver its ANCHOR and any plot '
        'commitment in exact terms — never soften or blur them.',
    'Continue seamlessly from <previous_prose>: same positions, same things '
        'in hand, same time of day. Getting anywhere or picking anything up '
        'takes a visible action.',
    'Stay in the viewpoint character\'s head and tense. Other people\'s '
        'thoughts are only what can be seen or guessed.',
    'Lead with the body: weight, sound, temperature, texture before visual '
        'cataloguing. Name feelings through what they do to someone, not '
        'with labels ("crushing sadness") or stock gestures ("breath '
        'hitched", "heart stuttered").',
    'When more than one person is present, they talk — and push back — as '
        'they move. Give each a distinct way of speaking. Use "said" '
        'sparingly and never "hissed" or "growled".',
    'No lectures: history and lore come out sideways, through what people '
        'take for granted.',
    'Vary sentence length naturally. Never three or more sentences of under '
        'four words in a row.',
    'Call people by name or pronoun, never "the older man" or "the blonde".',
    'No screenplay language (camera, cut to, fade). No chapter headings, no '
        'notes, nothing but the story.',
  ];

  static const _audioRules = [
    'Write only the beat marked CURRENT, as a script. Deliver its ANCHOR and '
        'any plot commitment in exact terms.',
    'Every line starts with a speaker label in capitals and a colon: '
        '"NARRATOR:" for description and action, or the character\'s first '
        'name for speech ("MARA:"). One speaker per line.',
    'The narrator carries place, movement and what faces show, in short '
        'spoken-aloud sentences. No stage directions in brackets, no sound '
        'effect cues, no parentheticals: everything is voiced.',
    'Characters say what they mean to each other, not to the listener. '
        'Give each a distinct way of speaking.',
    'Continue seamlessly from <previous_prose>.',
    'No headings or notes; only script lines.',
  ];

  /// Words the writer must avoid: the user's list plus the rolling one.
  static String bannedBlock(StoryProject p) {
    final all = {...p.bannedPhrases, ...p.autoBannedPhrases}
      ..removeWhere((s) => s.trim().isEmpty);
    return StudioContext.block(
      'banned_phrases',
      all.isEmpty
          ? ''
          : 'Do not use these words or phrases; they are worn out in this '
                'story: ${all.map((s) => '"$s"').join(', ')}.',
    );
  }

  static String _dialogueTarget(StoryProject p, StoryScene scene) {
    if (scene.castNames.length < 2) {
      return 'One character alone: a little muttering or thinking aloud is '
          'natural; no speeches.';
    }
    return switch (p.dialogueDensity) {
      'Dialogue-Heavy' =>
        'Several characters: speech should be roughly half the words.',
      'Sparse' =>
        'Several characters: keep speech brief but present — at least a few '
            'exchanged lines.',
      _ =>
        'Several characters: speech should be a fifth to a third of the '
            'words.',
    };
  }

  static String write(
    StoryProject p,
    int act,
    int index,
    int beat, {
    required String previousProse,
    String lore = '',
    String directive = '',
    String? feedback,
    String? previous,
  }) {
    final scene = p.scenes[act]![index];
    final beats = p.beats['$act-$index'] ?? const <StoryBeat>[];
    final current = beats[beat];
    final audio = p.storyFormat == StoryFormat.audioDrama;
    final lens = StoryLenses.resolve(p, scene.lens);
    final rules = audio ? _audioRules : _proseRules;
    final first = act == 0 && index == 0 && beat == 0;
    final last = beat == beats.length - 1;
    return StudioContext.join([
      audio ? audioRole : writerRole,
      StudioContext.block(
        'writing_rules',
        (_small(p) && !audio ? rules.take(6) : rules)
            .map((r) => '- $r')
            .join('\n'),
      ),
      StudioContext.style(p),
      StudioContext.cast(
        p,
        only: scene.castNames,
        interviewChars: _small(p) ? 300 : 900,
      ),
      StudioContext.relationships(p, only: scene.castNames),
      sceneBlueprint(p, act, index),
      beatList(beats),
      if (p.lensesEnabled && !audio)
        StudioContext.block('writing_lens', '${lens.name}: ${lens.prompt}'),
      StudioContext.block(
        'scene_intensity',
        StoryLenses.tensionInstruction(scene.tension),
      ),
      StudioContext.block('dialogue_target', _dialogueTarget(p, scene)),
      StudioContext.storySoFar(p, act, index),
      StudioContext.continuity(p, act, index, cast: scene.castNames),
      StudioContext.block('relevant_lore', lore),
      bannedBlock(p),
      StudioContext.block('author_directive', directive),
      StudioContext.block(
        'previous_prose',
        previousProse.isEmpty
            ? (first
                  ? 'This is the opening of the story. The reader knows '
                        'nothing yet: ground them in who, where and when '
                        'through action, and open with a hook.'
                  : 'This is the first beat of the scene.')
            : previousProse,
      ),
      StudioContext.retry(previous, feedback),
      'CURRENT: Beat ${current.number} of ${beats.length}. Write about '
          '${StoryPacing.wordsPerBeat} words.'
          '${last ? ' This beat closes the scene: land its exit conditions and stop.' : ' Stop where the next beat begins.'}',
      'FORMAT: Put the ${audio ? 'script' : 'prose'} inside '
          '<prose_text>…</prose_text> and write nothing outside it.',
    ]);
  }

  // ── Continuity check and surgical fix ──────────────────────────────────

  static const continuityRole =
      'You are a copy editor checking one freshly written passage for '
      'continuity and fidelity to its plan.';

  static String continuityReview(
    StoryProject p,
    int act,
    int index,
    int beat, {
    required String previousProse,
    required String prose,
  }) {
    final scene = p.scenes[act]![index];
    final current = (p.beats['$act-$index'] ?? const <StoryBeat>[])[beat];
    return StudioContext.join([
      continuityRole,
      StudioContext.block(
        'review_criteria',
        '''
FAIL for any of these, quoting the offending words:
1. The beat's ANCHOR or a plot commitment is missing, softened or changed.
2. Continuity with <previous_prose> or <continuity_ledger> is broken: someone is somewhere they could not be, holds something they put down, has lost an injury, or the time of day jumped.
3. A character appears or vanishes without getting there, or is called by the wrong name.
4. The viewpoint or tense slips, or another character's private thoughts are stated as fact.
5. The same static posture or gesture from the previous passage is simply repeated.
6. Screenplay language (camera, cut to), or three or more sentences of under four words in a row.

Do NOT fail for taste: word choice, rhythm you would have done differently, or a filter word here and there. PASS when none of the six applies.''',
      ),
      StudioContext.block('characters_present', scene.castNames.join(', ')),
      StudioContext.block(
        'point_of_view',
        '${p.pov}${scene.pov.isEmpty ? '' : ', through ${scene.pov}'}',
      ),
      StudioContext.continuity(p, act, index, cast: scene.castNames),
      StudioContext.block(
        'beat_plan',
        '[${current.type}] ${current.description}'
            '${current.anchor.isEmpty ? '' : '\nANCHOR: ${current.anchor}'}'
            '${scene.commitments.isEmpty ? '' : '\nScene commitments: ${scene.commitments}'}',
      ),
      StudioContext.block(
        'previous_prose',
        previousProse.isEmpty
            ? '(This passage opens the scene.)'
            : previousProse,
      ),
      StudioContext.block('generated_prose', prose),
      '''${StudioContext.tagsOnly}
<response>
  <issues>
    <issue>
      <severity>CRITICAL</severity> <!-- CRITICAL | MAJOR | MINOR -->
      <description>What is wrong, e.g. "Joss was sitting on the wagon step in the previous passage, but here he is standing at the gate."</description>
      <location>The exact words from the passage.</location>
      <fix_suggestion>The smallest change that fixes it.</fix_suggestion>
    </issue>
  </issues>
  <status>PASS</status> <!-- or FAIL -->
</response>''',
    ]);
  }

  static const fixRole =
      'You are a surgical editor. Fix the listed problems in the passage '
      'with the smallest possible edits.';

  static const _editFormat = '''FORMAT: Answer only with edit blocks:
<edits>
  <edit>
    <find>Words copied character for character from the passage — enough to be unique, as few as possible.</find>
    <replace>What they become.</replace>
  </edit>
</edits>''';

  static String fix({
    required String prose,
    required String problems,
    String previousProse = '',
  }) => StudioContext.join([
    fixRole,
    StudioContext.block('edit_rules', '''
- Change only what the problems require. Do not rewrite the passage or polish anything else.
- Quote <find> exactly as written, punctuation and quote marks included.
- Keep the tense and voice of the surrounding text.
- One edit per problem where possible.'''),
    StudioContext.block('previous_prose', previousProse),
    StudioContext.block('passage', prose),
    StudioContext.block('problems', problems),
    _editFormat,
  ]);

  static const bannedFixRole =
      'You are a surgical editor. Replace the worn-out phrases in the '
      'passage with fresh wording.';

  static String bannedFix({
    required String prose,
    required List<String> phrases,
  }) => StudioContext.join([
    bannedFixRole,
    StudioContext.block('edit_rules', '''
- For each listed phrase that appears, rewrite just the clause around it so the phrase is gone and the meaning stays.
- Do not swap one cliché for another. Change nothing else.
- Quote <find> exactly as written.'''),
    StudioContext.block('passage', prose),
    StudioContext.block('phrases', phrases.map((s) => '- $s').join('\n')),
    _editFormat,
  ]);

  /// Apply a user or Director instruction to written prose, surgically.
  static const patchRole =
      'You are a surgical prose editor. Apply the instruction to the passage '
      'with the smallest edits that fully satisfy it.';

  static String patch({required String prose, required String instruction}) =>
      StudioContext.join([
        patchRole,
        StudioContext.block('edit_rules', '''
- Touch only what the instruction needs: add a detail, change a line of dialogue, adjust a fact. Leave everything else exactly as it is.
- To add something, use a <find> of the sentence it attaches to and repeat that sentence in <replace> with the addition.
- Quote <find> exactly as written. Keep tense, viewpoint and voice.'''),
        StudioContext.block('passage', prose),
        StudioContext.block('instruction', instruction),
        _editFormat,
      ]);
}
