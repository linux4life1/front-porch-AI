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

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Memory & Heart group card: Journal (+ Dreams, Promises), Pockets (+ Hand
/// things between characters), Growth Rings, Objectives (+ Ambitions, Planner),
/// and Standing Mood. Aligned across desktop and web.
class PorchLifeMemoryGroup extends StatelessWidget {
  const PorchLifeMemoryGroup({
    super.key,
    required this.storage,
    required this.expandDetailsSignal,
    required this.forceExpandVersion,
    required this.highlightedId,
    required this.rowKeyFor,
    required this.onJumpTo,
  });

  final StorageService storage;
  final ExpandSignal? expandDetailsSignal;
  final int forceExpandVersion;
  final String? highlightedId;
  final Key Function(String id) rowKeyFor;
  final ValueChanged<String> onJumpTo;

  @override
  Widget build(BuildContext context) {
    final realism = storage.realismSettings;
    final memory = storage.memorySettings;
    final timeOn = realism.passageOfTimeDefault;
    final journalOn = memory.journalEnabled;
    final objectivesOn = realism.objectivesEnabled;
    final pocketsOn = realism.pocketsEnabled;
    final growthOn = memory.characterEvolutionEnabled;
    // Boons & Bogies genuinely cannot function without Growth — nothing can
    // advance or be proposed (docs/design/boons-and-bogies.md §8).
    final boonsBogiesOn = growthOn && memory.boonsBogiesEnabled;

    return FeatureGroupCard(
      title: 'Memory & Heart',
      subtitle: 'what they keep and carry',
      accentTint: AppColors.journalAccentOf(context),
      forceExpandVersion: forceExpandVersion,
      rows: [
        FeatureTreeNode(
          active: journalOn,
          parent: FeatureRow(
            key: rowKeyFor('journal'),
            icon: Icons.menu_book_outlined,
            label: 'The Journal',
            subtitle: 'Keeps per-chat memory cards and a "where we are" recap.',
            need: FeatureNeed.alone,
            highlighted: highlightedId == 'journal',
            expandDetailsSignal: expandDetailsSignal,
            blurb:
                'Memory cards and the "where we are" recap, kept per chat and '
                'never shared between chats. With the Realism Engine on, '
                'cards also carry the feeling of the moment; without it they '
                'are simply remembered.',
            value: journalOn,
            onChanged: memory.setJournalEnabled,
          ),
          children: [
            FeatureRow(
              icon: Icons.nightlight_outlined,
              label: 'Dreams',
              subtitle:
                  'Generates a hazy dream scene from memories, mood, and weather overnight.',
              need: FeatureNeed.needs,
              dependsOn: 'Passage of Time',
              satisfied: journalOn && timeOn,
              showDependencyBadge: true,
              expandDetailsSignal: expandDetailsSignal,
              onDependencyTap: () =>
                  onJumpTo(journalOn ? 'passage_of_time' : 'journal'),
              blurb:
                  'When a story night passes, the character dreams — a short, '
                  'hazy scene woven from their memories, mood and the weather.',
              value: realism.dreamsEnabled,
              onChanged: realism.setDreamsEnabled,
            ),
            FeatureRow(
              icon: Icons.handshake_outlined,
              label: 'Promises',
              subtitle:
                  'Tracks commitments made in chat so kept or broken promises matter later.',
              need: FeatureNeed.needs,
              dependsOn: 'the Journal',
              satisfied: journalOn,
              expandDetailsSignal: expandDetailsSignal,
              onDependencyTap: () => onJumpTo('journal'),
              blurb:
                  'Commitments either of you make are remembered, and kept or '
                  'broken ones come back later. Uses one extra AI request per '
                  'reply to spot them, so it is slower and costs more on a paid '
                  'API. You can settle one yourself in the Journal\'s Promises '
                  'tab.',
              value: realism.promiseLedgerEnabled,
              onChanged: realism.setPromiseLedgerEnabled,
            ),
          ],
        ),
        FeatureTreeNode(
          active: pocketsOn,
          parent: FeatureRow(
            key: rowKeyFor('pockets'),
            icon: Icons.checkroom_outlined,
            label: 'Pockets & Wardrobe',
            subtitle:
                'Remembers carried items and worn clothes, including wear and changes.',
            need: FeatureNeed.alone,
            highlighted: highlightedId == 'pockets',
            expandDetailsSignal: expandDetailsSignal,
            blurb:
                'What they are wearing and carrying is remembered instead of '
                'scrolling out of the conversation — so the keys they picked '
                'up an hour ago are still in their pocket, and the coat they '
                'took off is still off. Items can change: a candy bar becomes '
                'a wrapper, a sword gets notched. Uses one extra AI request '
                'per reply to notice what changed, so it is slower and costs '
                'more on a paid API. Kept per chat and cleared with it.',
            value: pocketsOn,
            onChanged: realism.setPocketsEnabled,
          ),
          children: [
            FeatureRow(
              icon: Icons.swap_horiz,
              label: 'Hand things between characters',
              subtitle:
                  'Moves handed-over items between pockets in group chats.',
              need: FeatureNeed.needs,
              dependsOn: 'Pockets & Wardrobe',
              satisfied: pocketsOn,
              expandDetailsSignal: expandDetailsSignal,
              onDependencyTap: () => onJumpTo('pockets'),
              blurb:
                  'In a group chat, when one character hands something to '
                  'another it actually moves — out of their pocket and into '
                  'the other\'s, keeping whatever condition it was in. Without '
                  'this, a handed-over item simply leaves the giver and reaches '
                  'no one. Costs nothing extra; it rides the check Pockets is '
                  'already doing. Best with a frontier model (Claude, GPT, '
                  'Gemini): it has to name WHO received the thing, which is '
                  'harder than noticing what changed, and smaller local models '
                  'often get the name wrong. When the name does not match '
                  'somebody in the chat, the app declines to guess — the item '
                  'leaves the giver and goes nowhere, exactly as before.',
              value: realism.pocketTransfersEnabled,
              onChanged: realism.setPocketTransfersEnabled,
            ),
          ],
        ),
        FeatureTreeNode(
          active: growthOn,
          parent: FeatureRow(
            key: rowKeyFor('growth'),
            icon: Icons.spa_outlined,
            label: 'Growth Rings',
            subtitle:
                'Adds lived experience as slow layers without rewriting who they are.',
            need: FeatureNeed.alone,
            highlighted: highlightedId == 'growth',
            expandDetailsSignal: expandDetailsSignal,
            blurb:
                'Slow character evolution — rings, not rewrites. What they '
                'live through is added as a new layer instead of overwriting '
                'who they were.',
            value: growthOn,
            onChanged: memory.setCharacterEvolutionEnabled,
          ),
          children: [
            FeatureTreeNode(
              active: boonsBogiesOn,
              parent: FeatureRow(
                key: rowKeyFor('boons-bogies'),
                icon: Icons.auto_awesome,
                label: 'Boons & Bogies',
                subtitle:
                    'Abilities that grow and flaws that surface. New ones always ask you first.',
                need: FeatureNeed.needs,
                dependsOn: 'Growth Rings',
                satisfied: growthOn,
                highlighted: highlightedId == 'boons-bogies',
                onDependencyTap: () => onJumpTo('growth'),
                expandDetailsSignal: expandDetailsSignal,
                blurb:
                    'A boon is an ability that gets better as the story uses '
                    'it; a bogey is a flaw that shows up now and then on a '
                    'roll. A growing boon can wear a bogey down until the '
                    'character overcomes it. New boons, new bogies, a trait '
                    'reaching Master and an overcome always ask you first. '
                    'Off keeps every existing boon and bogey in the chat — '
                    'nothing is deleted, and no kits are copied into new '
                    'chats.',
                value: memory.boonsBogiesEnabled,
                onChanged: memory.setBoonsBogiesEnabled,
              ),
              children: [
                FeatureRow(
                  key: rowKeyFor('bogey-rolls'),
                  icon: Icons.casino_outlined,
                  label: 'Bogey rolls',
                  subtitle:
                      'Let flaws show up now and then. Off keeps progression only.',
                  need: FeatureNeed.needs,
                  dependsOn: 'Boons & Bogies',
                  satisfied: boonsBogiesOn,
                  highlighted: highlightedId == 'bogey-rolls',
                  onDependencyTap: () => onJumpTo('boons-bogies'),
                  expandDetailsSignal: expandDetailsSignal,
                  blurb:
                      'A pressure gauge decides when a flaw shows up: never '
                      'every turn, never twice in a row, but always '
                      'eventually. Off leaves boons growing and bogies on '
                      'record without letting one fire in the story.',
                  value: memory.bogeyRollsEnabled,
                  onChanged: memory.setBogeyRollsEnabled,
                ),
                FeatureRow(
                  key: rowKeyFor('milestone-popups'),
                  icon: Icons.celebration_outlined,
                  label: 'Milestone popups',
                  subtitle:
                      'Center-screen moments. Off sends proposals to the Growth panel.',
                  need: FeatureNeed.needs,
                  dependsOn: 'Boons & Bogies',
                  satisfied: boonsBogiesOn,
                  highlighted: highlightedId == 'milestone-popups',
                  onDependencyTap: () => onJumpTo('boons-bogies'),
                  expandDetailsSignal: expandDetailsSignal,
                  blurb:
                      'The center-screen moment when something is accepted: '
                      'confetti for a boon, purple smoke for a bogey. Off '
                      'sends every proposal to the Growth panel\'s review '
                      'list and Moments list instead — nothing is lost, it '
                      'just waits for you.',
                  value: memory.milestonePopupsEnabled,
                  onChanged: memory.setMilestonePopupsEnabled,
                ),
              ],
            ),
          ],
        ),
        FeatureTreeNode(
          active: objectivesOn,
          parent: FeatureRow(
            key: rowKeyFor('objectives'),
            icon: Icons.track_changes,
            label: 'Objectives',
            subtitle:
                'Short-lived quests checked every few messages and after time skips.',
            need: FeatureNeed.alone,
            highlighted: highlightedId == 'objectives',
            expandDetailsSignal: expandDetailsSignal,
            blurb:
                'Short-lived quests a character works toward — set your own, '
                'or let them decide what they want. Needs nothing else to '
                'run, but it does check in with the AI every few messages '
                '(and after a time skip) to see where each goal stands. '
                'Switching this off is the way to stop that cost — your '
                'quests are kept either way.',
            value: objectivesOn,
            onChanged: realism.setObjectivesEnabled,
          ),
          children: [
            FeatureRow(
              icon: Icons.flag_outlined,
              label: 'Ambitions',
              subtitle:
                  'Long-term card goals nudged forward whenever an objective finishes.',
              need: FeatureNeed.needs,
              dependsOn: 'Objectives',
              satisfied: objectivesOn,
              expandDetailsSignal: expandDetailsSignal,
              onDependencyTap: () => onJumpTo('objectives'),
              blurb:
                  'Long-term goals written on the character\'s card colour how '
                  'they steer a scene, and finishing an objective moves them a '
                  'little closer. Costs nothing extra — the goals are already '
                  'on the card — but finishing a quest is the only thing that '
                  'moves them, so they need Objectives running.',
              value: realism.ambitionsEnabled,
              onChanged: realism.setAmbitionsEnabled,
            ),
            PlannerFeatureRow(
              value: realism.plannerEnabled,
              timeOn: timeOn,
              objectivesOn: objectivesOn,
              journalOn: journalOn,
              expandDetailsSignal: expandDetailsSignal,
              onDependencyTap: () => onJumpTo(
                !timeOn
                    ? 'passage_of_time'
                    : !objectivesOn
                    ? 'objectives'
                    : 'journal',
              ),
              onChanged: realism.setPlannerEnabled,
            ),
          ],
        ),
        FeatureRow(
          icon: Icons.cloud_queue,
          label: 'Standing Mood',
          subtitle:
              'Gives characters a baseline mood from their own tracked day, free.',
          need: FeatureNeed.alone,
          expandDetailsSignal: expandDetailsSignal,
          blurb:
              'Lets them arrive already in a mood you had nothing to do '
              'with — tired, hungry, worn down by a week of rain, or '
              'cheerful after a good night. Everything else in the app '
              'reacts to YOU, which slowly makes you the centre of their '
              'world; this is the part that is just their day. It is never '
              'invented: it comes from what the app already tracks, and '
              'hovering the mood chip tells you exactly what they walked '
              'in carrying, so you can always tell their day from your '
              'doing. Costs nothing — no extra AI request.',
          value: realism.standingMoodEnabled,
          onChanged: realism.setStandingMoodEnabled,
        ),
      ],
    );
  }
}
