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

// Canned replies for the Studio engine's stages, routed by the role
// sentence each prompt opens with (the `*Role` constants the prompts
// export, so a reworded prompt cannot silently fall through to the chat
// reply). Minimal story: 2 scenes per sequence, 3 beats per scene.

import 'package:front_porch_ai/services/story/story.dart';

/// The Studio stage [content] asks for and its reply, or null when the
/// prompt is not a Studio stage.
({String stage, List<String> pieces})? studioStoryReply(String content) {
  bool has(String role) => content.contains(role);
  if (has(StudioBiblePrompts.foundationRole)) {
    return (stage: 'foundation', pieces: [_foundation]);
  }
  if (has(StudioBiblePrompts.interviewRole)) {
    return (stage: 'interview', pieces: [_interview]);
  }
  if (has(StudioBiblePrompts.arcReviewRole)) {
    return (stage: 'arc-review', pieces: [_pass]);
  }
  if (has(StudioBiblePrompts.arcRole)) return (stage: 'arc', pieces: [_arc]);
  if (has(StudioStructurePrompts.actsReviewRole)) {
    return (stage: 'acts-review', pieces: [_pass]);
  }
  if (has(StudioStructurePrompts.actsRole)) {
    return (stage: 'acts', pieces: [_acts]);
  }
  if (has(StudioStructurePrompts.sequencesReviewRole)) {
    return (stage: 'sequences-review', pieces: [_pass]);
  }
  if (has(StudioStructurePrompts.sequencesRole)) {
    return (stage: 'sequences', pieces: [_sequences]);
  }
  if (has(StudioStructurePrompts.scenesReviewRole)) {
    return (stage: 'scenes-review', pieces: [_pass]);
  }
  if (has(StudioStructurePrompts.scenesRole)) {
    return (stage: 'scenes', pieces: [_scenes]);
  }
  if (has(StudioProsePrompts.beatsReviewRole)) {
    return (stage: 'beats-review', pieces: [_pass]);
  }
  if (has(StudioProsePrompts.beatsRole)) {
    return (stage: 'beats', pieces: [_beats]);
  }
  if (has(StudioProsePrompts.writerRole) || has(StudioProsePrompts.audioRole)) {
    // Several chunks on purpose: the running overlay's token counter is the
    // suite's streaming assertion.
    return (
      stage: 'write',
      pieces: [
        '<prose_text>The porch light blinked, ',
        'paused, and blinked again. ',
        'Wren counted the pulses twice before believing them: stay. ',
        List.filled(70, 'word').join(' '),
        '</prose_text>',
      ],
    );
  }
  if (has(StudioProsePrompts.continuityRole)) {
    return (stage: 'continuity', pieces: [_pass]);
  }
  if (has(StudioProsePrompts.fixRole) ||
      has(StudioProsePrompts.bannedFixRole)) {
    return (stage: 'fix', pieces: ['<edits></edits>']);
  }
  if (has(StudioProsePrompts.patchRole)) {
    return (
      stage: 'patch',
      pieces: [
        '<edits><edit><find>The porch light blinked,</find>'
            '<replace>The porch light blinked, smelling of lamp oil,</replace>'
            '</edit></edits>',
      ],
    );
  }
  if (has(StudioArchivePrompts.archivistRole)) {
    return (stage: 'archivist', pieces: [_archive]);
  }
  if (has(StudioArchivePrompts.summaryRole)) {
    return (
      stage: 'summary',
      pieces: [
        '<response><story_so_far>Wren read the light and answered it.'
            '</story_so_far></response>',
      ],
    );
  }
  if (has(DirectorPrompts.reviewRole)) {
    return (stage: 'director-review', pieces: [_pass]);
  }
  if (has(DirectorPrompts.plannerRole)) {
    return (stage: 'director', pieces: [_plan]);
  }
  return null;
}

const _pass = '<response><status>PASS</status></response>';

const _foundation = '''<response>
<genre_label>Cozy fantasy</genre_label><mood_label>Warm</mood_label>
<genre_classification>Small-town magic, played straight.</genre_classification>
<tone_and_atmosphere>Gentle and wry.</tone_and_atmosphere>
<writing_style_description>Close third person, plain sentences.</writing_style_description>
<status_quo>Wren tends the porch light alone each evening.</status_quo>
<character_briefs>
<brief><name>Wren</name><role>Protagonist — keeper of the light</role><description>Thirty, tired, kind.</description><core_flaw>Nobody will stay.</core_flaw><core_desire>To be waited for.</core_desire><vocal_cadence>Short, dry.</vocal_cadence></brief>
<brief><name>Dov Marsh</name><role>Supporting</role><description>The postman.</description><core_flaw>Avoids goodbyes.</core_flaw><core_desire>To matter.</core_desire><vocal_cadence>Rambling.</vocal_cadence></brief>
</character_briefs>
<relationship_matrix><relationship><from>Wren</from><to>Dov Marsh</to><feeling>Fond</feeling><note>old friends</note><hidden_tension>He knows about the letters.</hidden_tension><trust_level>7</trust_level></relationship></relationship_matrix>
<world_lore><entry><topic>The Porch</topic><detail>It remembers every guest.</detail></entry></world_lore>
</response>''';

final _interview =
    '<response><interview>${List.filled(40, 'Wren looks away and talks about the light. ').join()}</interview>'
    '<appearance>Thin, grey eyes, sleeves rolled.</appearance>'
    '<vocal_cadence>Short, dry.</vocal_cadence>'
    '<core_yearning>To be waited for.</core_yearning></response>';

const _arc = '''<response><global_arc>
<core_thematic_argument>Keeping a light for someone is a way of refusing to live.</core_thematic_argument>
<starting_value_state>Waiting</starting_value_state><ending_value_state>Leaving</ending_value_state>
<inciting_incident>One night the light flickers a message.</inciting_incident>
<major_surprises_and_twists>The message is from Wren herself.</major_surprises_and_twists>
</global_arc>
<narrative_threads>
<thread><thread_id>T1</thread_id><name>The flickering light</name><description>What the porch light is trying to say.</description></thread>
<thread><thread_id>T2</thread_id><name>Dov</name><description>The letters.</description></thread>
<thread><thread_id>T3</thread_id><name>Leaving</name><description>From waiting to walking.</description></thread>
</narrative_threads>
<character_arcs><arc><name>Wren</name><lie_believed>Nobody will stay.</lie_believed><truth_needed>She can leave.</truth_needed><arc_catalyst>The flicker.</arc_catalyst><arc_description>From waiting to walking.</arc_description></arc></character_arcs>
</response>''';

final _acts =
    '<response><acts>${[
      for (var i = 1; i <= 3; i++) '<act><number>$i</number><title>${['The Message in the Light', 'The Answer', 'The Road'][i - 1]}</title>'
            '<act_mandate>Act $i mandate.</act_mandate><threads><thread>T1</thread></threads></act>',
    ].join()}</acts></response>';

final _sequences =
    '<response><sequences>${[for (var i = 1; i <= 8; i++) '<sequence><number>$i</number><title>Sequence $i</title>'
          '<dramatic_question>Question $i?</dramatic_question>'
          '<description>What sequence $i does.</description>'
          '<ending_hook>Hook $i.</ending_hook></sequence>'].join()}</sequences></response>';

const _scenes = '''<response><scenes>
<scene><title>Reading the Flicker</title><valence_score>1</valence_score><scene_type>ACTION</scene_type><pov_character>Wren</pov_character>
<characters_present><character>Wren</character></characters_present><setting>The front porch</setting><narrative_lens>REFLECTION</narrative_lens>
<scene_objective>Count the pulses.</scene_objective><description>Wren counts the pulses and writes them down.</description>
<value_shift><start_state>wary</start_state><end_state>moved</end_state></value_shift><plot_commitments>None</plot_commitments>
<entrance_conditions>Dusk on the porch.</entrance_conditions><exit_conditions>The word is written down.</exit_conditions></scene>
<scene><title>Answering</title><valence_score>-1</valence_score><scene_type>REACTION</scene_type><pov_character>Wren</pov_character>
<characters_present><character>Wren</character><character>Dov Marsh</character></characters_present><setting>The kitchen</setting><narrative_lens>RELATIONAL</narrative_lens>
<scene_objective>Decide what to answer.</scene_objective><description>Wren tells Dov about the word.</description>
<value_shift><start_state>moved</start_state><end_state>resolved</end_state></value_shift><plot_commitments>None</plot_commitments>
<entrance_conditions>Later that night.</entrance_conditions><exit_conditions>Wren has decided.</exit_conditions></scene>
</scenes></response>''';

final _beats =
    '<response><beats>${[
      for (var i = 1; i <= 3; i++) '<beat><beat_type>${['SENSORY', 'REFLECTION', 'DIALOGUE'][i - 1]}</beat_type>'
            '<initiator>Wren</initiator><reactor>—</reactor>'
            '<action>Beat $i: the flicker spells a word.</action><reaction>—</reaction>'
            '<tactic>watches</tactic><subtext>hope</subtext><anchor>The word is stay.</anchor></beat>',
    ].join()}</beats></response>';

const _archive = '''<response>
<scene_summary>Wren read the flicker and wrote down the word stay.</scene_summary>
<continuity_facts><fact><category>Object</category><key>The notebook</key><detail>Holds the word "stay" in Wren's hand.</detail><character>Wren</character></fact></continuity_facts>
<relationship_updates></relationship_updates>
<cast_updates></cast_updates>
<new_characters></new_characters>
<lore_updates></lore_updates>
</response>''';

const _plan = '''<response>
<evaluation>Add the smell of lamp oil to the first scene.</evaluation>
<scope_kind>local</scope_kind>
<actions>
<action><action_type>EDIT_PROSE</action_type><scene>1.1</scene><summary>The porch light smells of lamp oil.</summary>
<details><instructions>Mention the smell of lamp oil when the light first blinks.</instructions></details></action>
</actions>
</response>''';
