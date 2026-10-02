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
import 'package:front_porch_ai/services/story/story_continuity.dart';

/// Studio memory stages: the end-of-scene archivist and the end-of-sequence
/// summary. Adapted from EllipsisProse (Apache-2.0, see NOTICE).
abstract final class StudioArchivePrompts {
  static const archivistRole =
      'You are a meticulous story archivist. Read the finished scene and '
      'record what later scenes must remember.';

  static String archivist(
    StoryProject p,
    int act,
    int index,
    String sceneText,
  ) {
    final scene = p.scenes[act]![index];
    return StudioContext.join([
      archivistRole,
      StudioContext.block(
        'archive_rules',
        '''
- Record only what the scene text actually established. Never invent, and never record plans from the blueprint that did not happen on the page.
- Continuity facts are concrete and reusable: a scar or what someone is wearing (Body), where an object is or who holds it (Object), a deal, debt or deadline with its exact terms (Promise), a room's layout or a feature of a place (Place), what someone now suspects or believes (Opinion), something someone learned (Knowledge). Not moods, not a plot recap.
- If a fact replaces an earlier one (the wagon was intact, now it is burned), use the same <key> so the old one is retired.
- Relationship updates only where a feeling really moved in this scene, with the moment that moved it.
- Lore is for new facts about the world itself. Do not repeat <known_lore_topics>.
- The summary is two or three plain sentences of what happened, for the story-so-far.''',
      ),
      StudioContext.block('cast_list', p.cast.map((c) => c.name).join(', ')),
      StudioContext.block(
        'known_lore_topics',
        p.lore.map((l) => l.topic).join(', '),
      ),
      StudioContext.relationships(p, only: scene.castNames),
      StudioContext.block(
        'scene',
        'Scene ${p.sceneLabel(act, index)}: ${scene.title}\n$sceneText',
      ),
      StudioContext.tagsOnly,
      '''<response>
  <scene_summary>What happened.</scene_summary>
  <continuity_facts>
    <fact>
      <category>${StoryContinuity.categories.join(' | ')}</category>
      <key>Short subject, e.g. "Teodor's left hand"</key>
      <detail>The concrete fact, e.g. "burned, bandaged".</detail>
      <character>Who it concerns, if anyone.</character>
    </fact>
  </continuity_facts>
  <relationship_updates>
    <update>
      <from>Name</from>
      <to>Name</to>
      <new_feeling>One or two words for how FROM now feels about TO.</new_feeling>
      <note>Two or three words of colour.</note>
      <hidden_tension>What is now unspoken between them.</hidden_tension>
      <trust_level>0-10</trust_level>
      <trigger>The moment that moved it.</trigger>
    </update>
  </relationship_updates>
  <cast_updates>
    <update>
      <name>Name</name>
      <story_events>What happened to them here, in a sentence.</story_events>
      <goals>How what they want has shifted, if it has.</goals>
    </update>
  </cast_updates>
  <new_characters>
    <character><name>Name</name><role>Role</role><description>Who they are.</description></character>
  </new_characters>
  <lore_updates>
    <entry><topic>Short name</topic><detail>The new fact about the world.</detail></entry>
  </lore_updates>
</response>''',
    ]);
  }

  static const summaryRole =
      'You are an editor keeping the "story so far" for a novel in progress.';

  /// Condense one finished sequence into a paragraph later stages can carry.
  static String sequenceSummary(
    StoryProject p,
    StorySequence sequence,
    String sceneSummaries,
  ) => StudioContext.join([
    summaryRole,
    StudioContext.block('summary_rules', '''
- Write one paragraph of at most 150 words covering what happened in this sequence, in order.
- Keep decisions that cannot be undone, revelations, and where people and relationships stand at the end.
- Plain narration, no commentary ("In this sequence…").'''),
    StudioContext.block(
      'sequence',
      'Sequence ${sequence.number}: ${sequence.title} — '
          '${sequence.dramaticQuestion}',
    ),
    StudioContext.block('scene_summaries', sceneSummaries),
    StudioContext.tagsOnly,
    '<response>\n  <story_so_far>The paragraph.</story_so_far>\n</response>',
  ]);
}
