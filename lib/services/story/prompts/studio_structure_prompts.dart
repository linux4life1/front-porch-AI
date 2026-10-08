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

/// Studio structure stages: acts, the eight sequences, and the scenes of one
/// sequence. Staging and theory adapted from EllipsisProse (Apache-2.0, see
/// NOTICE); `*Role` constants are stable opening lines the E2E backend
/// routes on.
abstract final class StudioStructurePrompts {
  static bool _small(StoryProject p) => p.promptTier == PromptTier.smallLocal;

  static const _mandateHeadings =
      'THEMATIC & STRUCTURAL FUNCTION, DRAMATIC ARC & PACING, THREAD '
      'PROGRESSION, CHARACTER JOURNEY, RISKS & CONSTRAINTS';

  // ── Acts ───────────────────────────────────────────────────────────────

  static const actsRole =
      'You are an author dividing your novel into its three acts.';

  static String acts(
    StoryProject p, {
    String canon = '',
    String? previous,
    String? feedback,
  }) => StudioContext.join([
    actsRole,
    StudioContext.block(
      'act_rules',
      '''
- Exactly three acts. Act 1: the world at rest and the break that ends it. Act 2: escalation, a midpoint that changes the game, and the lowest point. Act 3: the confrontation and the new normal.
- An act break is a one-way door: a revelation, a collapse or a choice after which nobody can go back.
- The acts will hold eight sequences: two in Act 1, four in Act 2, two in Act 3. Plan enough story for each.
- Each act causes the next ("therefore" or "but", never "and then").
- Give each act two or three knots: moments where threads collide and force a choice.
- Say where every thread stands at the end of each act. Drop nothing.
- Each <act_mandate> must cover, under these headings: $_mandateHeadings.${canon.isEmpty ? '' : '\n- <canon_events> are the spine. Spread them across the acts in order; invent only what connects them.'}''',
    ),
    StudioContext.style(p),
    StudioContext.storyInfo(p),
    StudioContext.threads(p),
    StudioContext.arcs(p),
    StudioContext.cast(p, tag: 'cast_list'),
    StudioContext.block('canon_events', canon),
    StudioContext.retry(previous, feedback),
    StudioContext.tagsOnly,
    '''<response>
  <acts>
    <act>
      <number>1</number>
      <title>Act title</title>
      <act_mandate>What this act must accomplish, under the five headings.</act_mandate>
      <world_building_developments>How the world opens up in this act.</world_building_developments>
      <threads><thread>T1</thread></threads>
      <knots>
        <knot><description>The event.</description><interaction>How one thread forces another.</interaction></knot>
      </knots>
      <thread_statuses_at_end>Where each thread stands when the act closes.</thread_statuses_at_end>
    </act>
    <!-- acts 2 and 3 -->
  </acts>
</response>''',
  ]);

  static const actsReviewRole =
      'You are a structural editor checking the three-act plan of a novel.';

  static String actsReview(StoryProject p, String generated) =>
      StudioContext.join([
        actsReviewRole,
        StudioContext.block(
          'review_criteria',
          '''
1. Are there exactly three acts, each with a mandate covering: $_mandateHeadings?
2. Is every act break a real one-way door, not a pause?
3. Is every thread accounted for at the end of every act?
4. Is there enough story for two sequences in Act 1, four in Act 2, two in Act 3?
5. Do reactions and stakes fit the genre and tone?

PASS when the plan is sound enough to build sequences on; note small suggestions without failing. FAIL only for a wrong act count, a missing mandate, an untracked thread, a severe pacing gap or a logic error.''',
        ),
        StudioContext.style(p),
        StudioContext.storyInfo(p),
        StudioContext.threads(p),
        StudioContext.block('generated_acts', generated),
        StudioBiblePrompts.reviewFormat,
      ]);

  // ── Sequences ──────────────────────────────────────────────────────────

  static const sequencesRole =
      'You are an author breaking your three acts into the eight sequences '
      'of the novel.';

  static String sequences(
    StoryProject p, {
    String canon = '',
    String? previous,
    String? feedback,
  }) => StudioContext.join([
    sequencesRole,
    StudioContext.block(
      'sequence_rules',
      '''
A sequence is a chain of scenes bound by one short-term goal: a character tries one approach against the world, and it resolves.
- Exactly eight sequences, with these jobs:
${StoryPacing.sequenceSlots.map((s) => '  ${s.number}. (Act ${s.act}) ${s.function} — ${s.brief}').join('\n')}
- Each sequence asks one concrete dramatic question ("Will she get the ledger back before the caravan leaves?"), different from every other sequence's.
- A sequence ends when its question is answered — success or failure — and its ending hook forces the next approach. Sequence N+1 starts exactly where N left everyone.
- At least one sequence in Act 2 must confront the protagonist's lie through something concrete: another person's conviction, a dilemma, or the cost of their own stubbornness.
- Say what each active thread does in the sequence and how the threads press on each other.
- Fit the "dark night" and the "confrontation" to the genre: in a romance they are emotional, in a legal thriller they happen in court.${canon.isEmpty ? '' : '\n- <canon_events> are the spine: place them in the sequences in the order they happened.'}''',
    ),
    StudioContext.style(p),
    StudioContext.storyInfo(p),
    StudioContext.threads(p),
    StudioContext.arcs(p),
    StudioContext.relationships(p),
    StudioContext.acts(p),
    StudioContext.block('canon_events', canon),
    StudioContext.retry(previous, feedback),
    StudioContext.tagsOnly,
    '''<response>
  <sequences>
    <sequence>
      <number>1</number>
      <parent_act>1</parent_act>
      <title>Sequence title</title>
      <sequence_function>${StoryPacing.sequenceSlots.first.function}</sequence_function>
      <dramatic_question>The question this sequence answers.</dramatic_question>
      <description>What happens and why it matters: the arc of the sequence, what each thread does, who is tested.</description>
      <threads_advanced><thread>T1</thread></threads_advanced>
      <sequence_climax>The moment the question is answered.</sequence_climax>
      <ending_hook>What pushes everyone into the next sequence.</ending_hook>
    </sequence>
    <!-- all eight -->
  </sequences>
</response>''',
  ]);

  static const sequencesReviewRole =
      'You are a structural editor checking the eight-sequence breakdown of '
      'a novel.';

  static String sequencesReview(StoryProject p, String generated) =>
      StudioContext.join([
        sequencesReviewRole,
        StudioContext.block(
          'review_criteria',
          '''
1. Exactly eight sequences: two in Act 1, four in Act 2, two in Act 3?
2. Does each have a sharp dramatic question of its own? Flag vague or repeated ones.
3. Does the end of each sequence force the next (therefore / but)?
4. Does an Act 2 sequence put real pressure on the protagonist's lie?
5. Does each sequence say what its threads do and how they collide?

PASS when the breakdown is sound; note small suggestions without failing. FAIL only for the wrong count, repeated sequence jobs, missing thread storylines or a severe causal gap.''',
        ),
        StudioContext.storyInfo(p),
        StudioContext.threads(p),
        StudioContext.acts(p),
        StudioContext.block('generated_sequences', generated),
        StudioBiblePrompts.reviewFormat,
      ]);

  // ── Scenes ─────────────────────────────────────────────────────────────

  static const scenesRole =
      'You are an author outlining the scenes of one sequence of your novel.';

  /// [act]/[firstScene] locate where the new scenes will start, for the
  /// story-so-far and continuity blocks.
  static String scenes(
    StoryProject p,
    StorySequence sequence, {
    required int act,
    required int firstScene,
    String canon = '',
    String? previous,
    String? feedback,
  }) {
    final pacing = StoryPacing.forTarget(p.targetWords);
    final budget = pacing.scenesFor(sequence.number);
    final rules = [
      'Write ${budget.min} to ${budget.max} scenes. Together they form a small '
          'story: something starts it, pressure builds, it turns, and there '
          'is fallout.',
      'A scene is one unbroken stretch of time and place where someone wants '
          'something and meets resistance. Start a new scene when the time or '
          'place jumps or the immediate goal is settled.',
      'Alternate ACTION scenes (someone pursues a goal and it goes wrong or '
          'costs them) with REACTION scenes (they absorb it and choose what '
          'to do next). In quiet genres the "disaster" is emotional: an '
          'interruption, a slip, an unexpected closeness.',
      'Tension: give each scene a score of 2 (peak), 1 (driving), -1 (low, '
          'transitional) or -2 (calm). Keep a running total; it must stay '
          'between -2 and 2, so a peak is followed by a breath and a lull by '
          'momentum.',
      'Every scene changes something for good: name the value at stake and '
          'how it shifts (e.g. trust to suspicion).',
      'Before choosing a turning point, think of the most obvious way the '
          'scene could resolve — and do not use it.',
      'Vary the settings. Do not strand the cast in one room scene after '
          'scene. Give each place a layout and objects people can use.',
      'The protagonist is not alone for more than two scenes running. Talk '
          'and friction between people drive the story.',
      'Plot commitments are exact: if there is a bet, a deadline, a promise '
          'or a reveal, state its precise terms.',
      'Say where and when each scene opens relative to the last, and how it '
          'closes. Skip travel and preparation unless something happens in it.',
      if (!_small(p))
        'In about half the scenes the complication comes from a subplot or a '
            "secondary character's own agenda, not the main opponent.",
      if (!_small(p))
        'Where possible, the protagonist cannot get what they want in the '
            'scene without giving up something they believe in.',
      if (p.lensesEnabled)
        'Pick one narrative lens per scene from <narrative_lenses> — the one '
            'that suits what the scene is doing. Use the id exactly.',
      'Do not resolve what belongs to later sequences.',
      if (canon.isNotEmpty)
        '<canon_events> are the spine: scenes dramatise the events that fall '
            'in this sequence, in order.',
      if (p.faithfulMode) StudioContext.noNewPeople,
    ];
    return StudioContext.join([
      scenesRole,
      StudioContext.block('scene_rules', rules.map((r) => '- $r').join('\n')),
      StudioContext.style(p),
      StudioContext.storyInfo(p),
      StudioContext.threads(p),
      StudioContext.cast(p),
      StudioContext.arcs(p),
      StudioContext.relationships(p),
      if (p.lensesEnabled)
        StudioContext.block('narrative_lenses', StoryLenses.catalog(p)),
      StudioContext.acts(p),
      StudioContext.block('canon_events', canon),
      StudioContext.storySoFar(p, act, firstScene),
      StudioContext.continuity(p, act, firstScene),
      StudioContext.sequences(p, sequence.number),
      StudioContext.retry(previous, feedback),
      StudioContext.tagsOnly,
      '''<response>
  <scenes>
    <scene>
      <title>Scene title</title>
      <valence_score>1</valence_score>
      <valence_running_sum>1</valence_running_sum>
      <scene_type>ACTION</scene_type> <!-- or REACTION -->
      <pov_character>Full name</pov_character>
      <characters_present><character>Full name</character></characters_present>
      <threads_advanced><thread>T1</thread></threads_advanced>
      <setting>Place, time of day, and the layout and objects that matter.</setting>
      ${p.lensesEnabled ? '<narrative_lens>LENS_ID</narrative_lens>' : ''}
      <scene_objective>What this scene is for.</scene_objective>
      <description>What happens: how it opens, the complications, the turning point, how it ends.</description>
      <value_shift><start_state>e.g. hope</start_state><end_state>e.g. dread</end_state></value_shift>
      <plot_commitments>Exact promises, terms, reveals or deadlines the prose must deliver — or "None".</plot_commitments>
      <entrance_conditions>Where everyone is and how much time has passed since the last scene.</entrance_conditions>
      <exit_conditions>Where everyone is when it closes and what has changed.</exit_conditions>
    </scene>
  </scenes>
  <new_characters>
    <character><name>Only if truly needed</name><role>Role</role><description>Who they are.</description></character>
  </new_characters>
</response>''',
    ]);
  }

  static const scenesReviewRole =
      'You are a developmental editor auditing the scene outline of one '
      'sequence.';

  static String scenesReview(
    StoryProject p,
    StorySequence sequence,
    String generated,
  ) {
    final budget = StoryPacing.forTarget(
      p.targetWords,
    ).scenesFor(sequence.number);
    return StudioContext.join([
      scenesReviewRole,
      StudioContext.block(
        'review_criteria',
        '''
1. Count: ${budget.min} to ${budget.max} scenes?
2. Does each scene change something for good (a real value shift), or do some merely pass time?
3. Cause and effect: does each scene follow from the last, and does the sequence answer its dramatic question?
4. Tension: does the running total stay between -2 and 2, with peaks followed by a breath?
5. Are plot commitments stated in exact terms?
6. Variety: do settings change, and is the protagonist never alone for more than two scenes running?
7. Does anything contradict the story so far or the cast?

PASS when the outline is sound; note small suggestions without failing. FAIL only for a wrong scene count, scenes with no change, a broken causal chain or a contradiction of established facts.''',
      ),
      StudioContext.storyInfo(p),
      StudioContext.cast(p, tag: 'cast_list'),
      StudioContext.sequences(p, sequence.number),
      StudioContext.block('generated_scenes', generated),
      StudioBiblePrompts.reviewFormat,
    ]);
  }
}
