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

/// The Director: turn a plain-language request into a list of small,
/// targeted changes. Adapted from EllipsisProse's Directive Agent
/// (Apache-2.0, see NOTICE).
abstract final class DirectorPrompts {
  static const plannerRole =
      'You are a developmental editor. An author has asked for a change to '
      'their story; plan the smallest set of edits that fully delivers it.';

  /// The whole story on one page: what exists, what is written, who is in it.
  static String outline(StoryProject p) {
    final lines = <String>[];
    for (var act = 0; act < p.acts.length; act++) {
      lines.add('ACT ${p.acts[act].number}: ${p.acts[act].title}');
      for (final seq in p.sequencesInAct(act)) {
        lines.add(
          '  SEQUENCE ${seq.number}: ${seq.title}'
          '${seq.dramaticQuestion.isEmpty ? '' : ' — ${seq.dramaticQuestion}'}',
        );
        for (final i in p.sceneIndexesInSequence(seq.number)) {
          final s = p.scenes[act]![i];
          final beats = p.beats['$act-$i'] ?? const <StoryBeat>[];
          final state = p.sceneHasProse(act, i)
              ? 'written'
              : (beats.isEmpty ? 'outline only' : 'beats planned');
          final what = s.summary.isNotEmpty ? s.summary : s.description;
          lines.add(
            '    ${p.sceneLabel(act, i)} [$state] ${s.title} '
            '(${s.castNames.join(', ')}) — '
            '${what.length > 220 ? '${what.substring(0, 220)}…' : what}',
          );
          for (final b in beats) {
            final d = b.description;
            lines.add(
              '      beat ${b.number}: '
              '${d.length > 110 ? '${d.substring(0, 110)}…' : d}',
            );
          }
        }
      }
    }
    return lines.join('\n');
  }

  static const _actions = '''
Story and cast:
- MODIFY_STORY — details: any of <title> <concept> <themes> <status_quo> <inciting_incident>.
- ADD_CHARACTER — details: <name> <role> <description> <core_flaw> <core_desire> <vocal_cadence>.
- MODIFY_CHARACTER — <character>; details: any of the fields above, or <secret>.
- DELETE_CHARACTER — <character>.
- MODIFY_RELATIONSHIP — details: <from> <to> <feeling> <note> <hidden_tension> <trust_level>.
- ADD_LORE / MODIFY_LORE — details: <topic> <detail>.
- ADD_FACT — details: <category> <key> <detail> <character>; optional <scene> it becomes true from.
Structure:
- MODIFY_ACT — <act>; details: <title> <act_mandate>.
- MODIFY_SEQUENCE — <sequence>; details: <title> <dramatic_question> <description>.
- ADD_SCENE — <sequence>, and optionally the <scene> it goes after; details: <title> <description> <characters> <setting> <scene_type> <narrative_lens> <scene_objective> <plot_commitments>.
- MODIFY_SCENE — <scene>; details: any scene field above, plus <instructions> saying how prose already written for it should change.
- DELETE_SCENE — <scene>.
- MOVE_SCENE — <scene>; details: <to_position> (its new place inside the same sequence, counting from 1).
Beats:
- INSERT_BEAT — <scene>, <beat> = the beat it goes after (0 = first); details: <beat_type> <initiator> <reactor> <action> <reaction> <subtext> <anchor>.
- MODIFY_BEAT — <scene> <beat>; details: any beat field, plus <instructions>.
- DELETE_BEAT — <scene> <beat>.
Prose:
- EDIT_PROSE — <scene>, optional <beat>; details: <instructions> for a small, targeted change to written prose (add a detail, change a line).
- REWRITE_PROSE — <scene>, optional <beat>; details: <instructions>. Throws the prose away and writes it again. Last resort.''';

  static String planner(
    StoryProject p, {
    required String directive,
    required bool protect,
    DirectorPlan? previousPlan,
    String refinement = '',
    String? previous,
    String? feedback,
  }) => StudioContext.join([
    plannerRole,
    StudioContext.block(
      'planning_rules',
      '''
- Prefer small edits to big ones: change a scene rather than delete it, patch prose rather than rewrite it.
- Refer to scenes by their label (e.g. 3.2), exactly as shown in <story_outline>.
- A change that ripples (a new secret, a changed motive) needs every place it touches: the character, the scenes that should hint at it, the facts it creates, the scene where it comes out. Set <scope_kind> to arc and list what must stay true in <consistency_notes>.
- Do not add scenes to a sequence that has none yet; change the sequence instead.
- Each action has a one-line <summary> the author will read.
${protect ? '- PROTECT WRITTEN PROSE is ON. For scenes marked [written], use only EDIT_PROSE or MODIFY_SCENE (both patch lines in place). If the request truly cannot be met without rewriting, deleting, moving or re-beating a written scene, still list that action and say so in <evaluation>; the author will have to unlock it.' : '- Written prose may be changed, but still prefer patches to rewrites.'}''',
    ),
    StudioContext.block('available_actions', _actions),
    StudioContext.storyInfo(p),
    StudioContext.cast(p, tag: 'cast_list'),
    StudioContext.relationships(p),
    StudioContext.block('story_outline', outline(p)),
    if (previousPlan != null)
      StudioContext.block(
        'previous_plan',
        previousPlan.actions
            .map((a) => '- ${a.type.wire}: ${a.summary}')
            .join('\n'),
      ),
    if (refinement.trim().isNotEmpty)
      StudioContext.block('refinement_request', refinement),
    if (refinement.trim().isNotEmpty)
      'Revise <previous_plan>: keep what the author did not ask to change '
          'and alter only what <refinement_request> requires. Return the '
          'full revised plan.',
    StudioContext.block('author_request', directive),
    StudioContext.retry(previous, feedback),
    StudioContext.tagsOnly,
    '''<response>
  <evaluation>How the request can be met with the least disruption.</evaluation>
  <scope_kind>local</scope_kind> <!-- or arc -->
  <consistency_notes>For arc scope: what must stay true across the scenes.</consistency_notes>
  <actions>
    <action>
      <action_type>MODIFY_SCENE</action_type>
      <scene>3.2</scene>
      <summary>Mara smells lamp oil on Teodor's coat.</summary>
      <details>
        <instructions>On the roof, Mara notices the smell of lamp oil on Teodor's coat and says nothing.</instructions>
      </details>
    </action>
  </actions>
</response>''',
  ]);

  static const reviewRole =
      'You are a continuity editor checking a plan of story changes before '
      'it is applied.';

  static String review(StoryProject p, DirectorPlan plan) =>
      StudioContext.join([
        reviewRole,
        StudioContext.block(
          'review_criteria',
          '''
1. Would the plan contradict something the story has already established (who knows what, where people are, what has happened)?
2. Does it leave the change half done — a secret planted but never revealed, a character removed but still in scenes?
3. Do the actions contradict each other?

PASS when the plan would leave the story consistent. FAIL only for a real contradiction or a clearly missing step, and say which.''',
        ),
        StudioContext.block('author_request', plan.directive),
        StudioContext.block('consistency_notes', plan.consistencyNotes),
        StudioContext.block('story_outline', outline(p)),
        StudioContext.block(
          'proposed_plan',
          plan.actions
              .map((a) {
                final where = a.sceneId.isEmpty
                    ? ''
                    : ' @ ${p.sceneLabelById(a.sceneId)}'
                          '${a.beat > 0 ? ' beat ${a.beat}' : ''}';
                return '- ${a.type.wire}$where: ${a.summary}';
              })
              .join('\n'),
        ),
        StudioBiblePrompts.reviewFormat,
      ]);
}
