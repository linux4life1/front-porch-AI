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
import 'package:front_porch_ai/services/story/prompts/studio_context.dart';

/// Studio bible stages: world foundation, character interviews, story arc.
///
/// The staging and the craft theory behind these prompts are adapted from
/// EllipsisProse (Apache-2.0, see NOTICE). Each `*Role` constant is the
/// prompt's opening line and stays stable: the E2E backend routes on it.
abstract final class StudioBiblePrompts {
  static const overusedNames =
      'Choose fresh names that fit this world. Never use these worn-out ones: '
      'Elara, Vance, Chloe, Silas, Thorne, Kaelan, Kaela, Kael, Voss, Lyra, '
      'Ezra, Kira.';

  static bool _small(StoryProject p) => p.promptTier == PromptTier.smallLocal;

  // ── World foundation ───────────────────────────────────────────────────

  static const foundationRole =
      'You are an author laying the foundation for a new story: its world, '
      'its tone, and its people, as they stand BEFORE the plot begins.';

  /// [cards] is the imported-character block and [canon] the chat-history
  /// block; either may be empty.
  static String foundation(
    StoryProject p, {
    String cards = '',
    String canon = '',
    String? previous,
    String? feedback,
  }) {
    final rules = [
      'Describe the ordinary world in equilibrium: place, era, rules, and the '
          'social and economic reality people live in. It must be internally '
          'consistent, whether it is a fantasy realm or a suburban kitchen.',
      'Do NOT write the inciting incident or any plot events. The plot is the '
          'next stage; here the world is still at rest, with its flaws showing.',
      'For each character give the lie they believe (their blind spot) and '
          'what they ache for: a human longing such as dignity, belonging, '
          'love or wonder — never a task list.',
      'People are not machines. Avoid cold "mastermind" characters who treat '
          'feelings as numbers unless the concept asks for one.',
      'Nobody exists alone: say how the main characters already feel about '
          'each other, including what goes unsaid.',
      if (!_small(p))
        'If the concept mixes clashing tones, do not average them. Say '
            'exactly how they combine into one specific voice.',
      if (cards.isNotEmpty)
        'The people in <required_cast> are the core cast. Keep their names, '
            'personalities and bonds true to their definitions. '
            '${p.faithfulMode && canon.isNotEmpty ? 'This is a faithful retelling: the only other people you may add are ones who actually appear in <canon_events>. Do not invent anyone.' : 'You may add supporting characters around them.'}',
      if (canon.isNotEmpty)
        'Take each core character\'s lie, longing and way of speaking from '
            'how they actually behaved in <canon_events>. Do not give them '
            'traits those events contradict.',
      if (canon.isNotEmpty)
        '<canon_events> really happened. The world and cast you describe must '
            'be the ones those events happened to.',
      if (canon.isNotEmpty)
        p.selectedGenres.isEmpty && p.selectedMoods.isEmpty
            ? 'No genre or mood was chosen: take both from <canon_events>, as '
                  'the chat itself played.'
            : 'The genre and mood in <author_preferences> are the lens '
                  '<canon_events> are told through. They never change what '
                  'happened. Write a genre contract and tone those events can '
                  'honestly be told in; where a preference cannot fit the '
                  'events, the events win.',
      overusedNames,
    ];
    return StudioContext.join([
      foundationRole,
      StudioContext.block(
        'foundation_rules',
        rules.map((r) => '- $r').join('\n'),
      ),
      StudioContext.block('concept', p.concept),
      StudioContext.preferences(p),
      StudioContext.block('required_cast', cards),
      StudioContext.block('canon_events', canon),
      StudioContext.retry(previous, feedback),
      StudioContext.tagsOnly,
      '''<response>
  <genre_label>Two to four words, e.g. "Cozy fantasy mystery".</genre_label>
  <mood_label>Two to four words, e.g. "Warm, wry".</mood_label>
  <genre_classification>The story's engine. Name one genre convention it plays straight and one it subverts, and what is off-limits in this world.</genre_classification>
  <tone_and_atmosphere>The emotional weather. Name two or three distinct published authors whose blend captures it, and say how the narration's focus shifts between action, reflection and dialogue.</tone_and_atmosphere>
  <writing_style_description>A manual for the prose writer: how the viewpoint character's biases colour what the narration notices; the sentence rhythm wanted (varied — no chains of tiny fragments); and one stylistic habit this book must avoid.</writing_style_description>
  <status_quo>Several paragraphs: setting, rules, history and the normal world before anything goes wrong.</status_quo>
  <character_briefs>
    <brief>
      <name>Full name</name>
      <role>Protagonist | Antagonist | Love Interest | Mentor | Supporting — plus one line on their place in the world.</role>
      <description>Two or three sentences: body, background, temperament.</description>
      <core_flaw>The lie they believe.</core_flaw>
      <core_desire>What they ache for.</core_desire>
      <vocal_cadence>How they talk: rhythm, vocabulary, habits.</vocal_cadence>
    </brief>
  </character_briefs>
  <relationship_matrix>
    <relationship>
      <from>Name</from>
      <to>Name</to>
      <feeling>One or two words for how FROM feels about TO, e.g. "Protective".</feeling>
      <note>Two or three words of colour, e.g. "owes him".</note>
      <hidden_tension>What goes unsaid between them.</hidden_tension>
      <trust_level>0-10</trust_level>
    </relationship>
  </relationship_matrix>
  <world_lore>
    <entry><topic>Short name</topic><detail>One concrete fact about the world.</detail></entry>
  </world_lore>
</response>''',
    ]);
  }

  // ── Character interview ────────────────────────────────────────────────

  static const interviewRole =
      'You are a novelist finding a character by letting them talk.';

  static const _questions = [
    'How do other people see you?',
    'How do you see yourself? What do you wish people knew?',
    'Where do you fit in this world — its class, its culture, its money?',
    'What do you look like?',
    'What do you wear when you want to feel like yourself?',
    'What do you do all day?',
    'Where do you come from, and how did you end up here?',
    'Tell us about a time you let someone down, and why you still think you were right.',
    'What accusation made you furious — and which part of it was true?',
    'What do you love?',
    'What do you hope for when it is quiet and nobody is asking?',
    'What makes your guard drop completely?',
    'What is an odd habit of yours?',
  ];

  static const _smallQuestions = [0, 3, 6, 7, 9, 10];

  static String interview(
    StoryProject p,
    StoryCastMember member, {
    String? previous,
    String? feedback,
  }) {
    final questions = _small(p)
        ? [for (final i in _smallQuestions) _questions[i]]
        : _questions;
    return StudioContext.join([
      interviewRole,
      StudioContext.block(
        'interview_method',
        '''
Write ${member.name}'s answers to the interview below as present-tense prose in their own unmistakable voice — speech, gesture, evasion and all. Do not label the questions; let each answer make its question obvious.
- A reader should be able to tell this person from anyone else by how they talk and what they dodge.
- Show contradiction: a bias, a defence, something they will not quite admit.
- Every answer must add something new — a detail, a history, a want. Do not circle the same trait.
- When asked what they look like, they must actually answer, however reluctantly.
- People contain multitudes: the serious one finds something funny; the busy one loves something useless.
- Stay inside the world as it stands. Do not invent future plot events.
${_small(p) ? '' : '''
Example of the register (a different character):
Julian doesn't look up from picking a burr out of the hem of his jeans. "My brother tells people I was 'difficult' back then. That's Mark's favorite word — makes him sound like a psychologist instead of a guy who sold our mother's silver." A short, tight smirk surfaces and vanishes. "I wasn't difficult. I was thirteen and the only person in that house who noticed the gas had been shut off."'''}''',
      ),
      StudioContext.block('questions', questions.map((q) => '- $q').join('\n')),
      StudioContext.block('concept', p.concept),
      StudioContext.block('status_quo', p.statusQuo),
      StudioContext.style(p),
      StudioContext.cast(p, tag: 'cast_list'),
      StudioContext.relationships(p),
      StudioContext.block('character_to_interview', '''
Name: ${member.name}
Role: ${member.role}
${member.description}
The lie they believe: ${member.flaw}
What they ache for: ${member.desire}
How they talk: ${member.voiceSample ?? ''}'''),
      StudioContext.retry(previous, feedback),
      StudioContext.tagsOnly,
      '''<response>
  <interview>The full interview, in their voice.</interview>
  <appearance>One plain paragraph describing how they look, for an illustrator: build, face, hair, usual clothes.</appearance>
  <vocal_cadence>How they talk, in one or two sentences.</vocal_cadence>
  <core_yearning>One or two sentences: what truly drives them.</core_yearning>
</response>''',
    ]);
  }

  // ── Story arc ──────────────────────────────────────────────────────────

  static const arcRole =
      'You are an author designing the dramatic engine of your novel: what '
      'breaks the world you were given, and what the story argues.';

  static String arc(
    StoryProject p, {
    String canon = '',
    String? previous,
    String? feedback,
  }) {
    final rules = [
      'Take <status_quo> as ground truth. Do not redesign the world.',
      'Inciting incident: one precise event that breaks the status quo and '
          'cannot be undone.',
      'Theme: a real argument a reasonable person could disagree with '
          '("Loyalty to the dead is a kind of cowardice"), never a slogan '
          '("Family matters").',
      'Scale the stakes to the genre: in a thriller, lives; in a romance, '
          'the heart and standing; in a quiet drama, who someone is.',
      'Threads: an A-story (the visible conflict), a B-story (a relationship '
          'that tests the theme from a personal side) and a C-story (the '
          "protagonist's inner change from the lie to the truth).",
      if (!_small(p))
        'Plan at least two reversals. For each: what the reader expects, what '
            'happens instead, and why it was inevitable.',
      if (!_small(p))
        "The climax must be won or lost through the protagonist's own "
            'choices and growth, never by luck or rescue.',
      'Use the existing cast. Do not invent a new character where one of '
          'them would do.',
      if (canon.isNotEmpty)
        '<canon_events> really happened and are the spine of this story: the '
            'arc must organise those events, not replace them.',
    ];
    return StudioContext.join([
      arcRole,
      StudioContext.block('arc_rules', rules.map((r) => '- $r').join('\n')),
      StudioContext.block('concept', p.concept),
      StudioContext.style(p),
      StudioContext.block('status_quo', p.statusQuo),
      StudioContext.cast(p, tag: 'cast_list'),
      StudioContext.relationships(p),
      StudioContext.block('canon_events', canon),
      StudioContext.retry(previous, feedback),
      StudioContext.tagsOnly,
      '''<response>
  <global_arc>
    <core_thematic_argument>The debatable thesis the story tests.</core_thematic_argument>
    <starting_value_state>Where the protagonist starts (living the lie).</starting_value_state>
    <ending_value_state>Where they end (the truth accepted, or tragically refused).</ending_value_state>
    <inciting_incident>The event that breaks the status quo.</inciting_incident>
    <major_surprises_and_twists>The planned reversals.</major_surprises_and_twists>
  </global_arc>
  <narrative_threads>
    <thread><thread_id>T1</thread_id><name>A-story name</name><description>The external conflict and what drives it.</description></thread>
    <thread><thread_id>T2</thread_id><name>B-story name</name><description>The relationship that tests the theme.</description></thread>
    <thread><thread_id>T3</thread_id><name>C-story name</name><description>The inner journey from lie to truth.</description></thread>
  </narrative_threads>
  <character_arcs>
    <arc>
      <name>Character name</name>
      <lie_believed>The false belief that steers them.</lie_believed>
      <truth_needed>What they must accept, or refuse.</truth_needed>
      <arc_catalyst>The event or person that forces the question.</arc_catalyst>
      <arc_description>The journey, with its resistance and its break.</arc_description>
    </arc>
  </character_arcs>
</response>''',
    ]);
  }

  static const arcReviewRole =
      'You are a story editor checking a story arc before a novel is built '
      'on it.';

  static String arcReview(StoryProject p, String generated) =>
      StudioContext.join([
        arcReviewRole,
        StudioContext.block(
          'review_criteria',
          '''
1. Theme: is <core_thematic_argument> a real, debatable argument rather than a slogan?
2. Inciting incident: is it one sharp, irreversible break that fits the genre?
3. Threads: at least three, each with a clear job; does the B-story test the theme?
4. Character arcs: does each give a specific lie, truth and catalyst? Do decisions, not coincidences, drive the plot?
5. Cast: was a new character invented where an existing one would do? Do stakes match the genre?

PASS when the arc clears all five well enough to build on; put small suggestions in <critique_analysis> without failing. FAIL only for: a slogan theme, no inciting incident, fewer than three threads, arcs missing a lie or a truth, or a plot-breaking logic error.''',
        ),
        StudioContext.block('concept', p.concept),
        StudioContext.style(p),
        StudioContext.block('status_quo', p.statusQuo),
        StudioContext.cast(p, tag: 'cast_list'),
        StudioContext.block('generated_story_arc', generated),
        reviewFormat,
      ]);

  /// Shared answer format for every reviewer.
  static const reviewFormat = '''${StudioContext.tagsOnly}
<response>
  <critique_analysis>Brief, specific findings.</critique_analysis>
  <status>PASS</status> <!-- or FAIL -->
  <deviation_reasons>
    <reason>Only when failing: the exact problem and how to fix it.</reason>
  </deviation_reasons>
</response>''';
}
