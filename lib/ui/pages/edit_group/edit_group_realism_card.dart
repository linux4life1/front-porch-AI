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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_stats.dart';
import 'package:front_porch_ai/services/database_rebind.dart' show liveDatabase;
import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_form_kit.dart';
import 'package:front_porch_ai/ui/pages/edit_group/edit_group_draft.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/theme/creator_palette.dart';
import 'package:front_porch_ai/ui/widgets/character_stats_section.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section/realism_form_section.dart';
import 'package:front_porch_ai/ui/widgets/relationship_scale.dart';
import 'package:front_porch_ai/ui/widgets/story_begins_row.dart';

/// Details 7: Realism Engine. What the cast shares for new chats: Time of
/// Day and Day Number, where the story begins, Chaos Mode, Realism
/// Verification and the starting feelings between members. Each member's own
/// Realism, relationship, emotion, Needs, Afterglow and Pockets are in their
/// card.
class EditGroupRealismCard extends StatelessWidget {
  const EditGroupRealismCard({
    super.key,
    required this.draft,
    required this.members,
    required this.onChanged,
  });

  final EditGroupDraft draft;
  final List<CharacterCard> members;
  final VoidCallback onChanged;

  String _id(CharacterCard c) => c.dbId ?? c.name;

  @override
  Widget build(BuildContext context) {
    final kit = EditCharacterFormKit(context);
    final amber = context.creatorPalette?.amber ?? AppColors.timeDayAccent;
    final label = TextStyle(
      color: context.creatorPalette?.prose ?? AppColors.textSecondary(context),
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    );
    return kit.sectionCard(
      icon: Icons.psychology_alt_outlined,
      title: 'Realism Engine',
      color: AppColors.formAccentOf(context),
      children: [
        kit.disclaimer('These settings only affect new chats with this group.'),
        const SizedBox(height: 12),
        Text(
          "Each member's Realism, starting relationship and emotion, Needs, "
          'Afterglow and Pockets are in their card, exactly where a 1:1 '
          'character keeps them. The shared scene is set here:',
          key: const Key('group-realism-intro'),
          style: label,
        ),
        const SizedBox(height: 16),
        RealismSectionHeader(Icons.schedule, 'Time & Day', amber),
        const SizedBox(height: 12),
        RealismTimeDayCard(
          timeOfDay: draft.timeOfDay,
          onTimeOfDayChanged: (v) {
            draft.setScene(time: v);
            onChanged();
          },
          dayCount: draft.dayCount,
          onDayCountChanged: (v) {
            draft.setScene(day: v);
            onChanged();
          },
          labelStyle: label,
        ),
        const SizedBox(height: 8),
        StoryBeginsRow(
          storyStartDate: draft.storyStartDate,
          onStoryStartDateChanged: (v) {
            draft.storyStartDate = v;
            onChanged();
          },
          storyStartTime: draft.storyStartTime,
          onStoryStartTimeChanged: (v) {
            draft.storyStartTime = v;
            onChanged();
          },
        ),
        const SizedBox(height: 16),
        realismChaosRow(
          context,
          value: draft.chaos,
          onChanged: (v) {
            draft.chaos = v;
            onChanged();
          },
        ),
        const SizedBox(height: 16),
        RealismVerificationControls(
          enabled: draft.verification,
          onEnabledChanged: (v) {
            draft.verification = v;
            onChanged();
          },
          maxReprocesses: draft.verificationMaxReprocesses,
          onMaxReprocessesChanged: (v) {
            draft.verificationMaxReprocesses = v;
            onChanged();
          },
          strictness: draft.verificationStrictness,
          onStrictnessChanged: (v) {
            draft.verificationStrictness = v;
            onChanged();
          },
          directorAuthority: draft.directorAuthority,
          onDirectorAuthorityChanged: (v) {
            draft.directorAuthority = v;
            onChanged();
          },
        ),
        if (members.length > 1) ...[
          const SizedBox(height: 16),
          Text(
            'Starting feelings between members',
            style: TextStyle(
              color: AppColors.formAccentOf(context),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              for (final from in members)
                for (final to in members)
                  if (_id(from) != _id(to)) _pair(context, from, to),
            ],
          ),
        ],
      ],
    );
  }

  Widget _pair(BuildContext context, CharacterCard from, CharacterCard to) {
    final score = draft.feelings[_id(from)]?[_id(to)] ?? 0;
    return SizedBox(
      width: 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${from.name} toward ${to.name} · ${relationshipTierName(score)}',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 11,
            ),
          ),
          Slider(
            key: Key('group-feeling-${_id(from)}-${_id(to)}'),
            value: score.toDouble().clamp(-300, 300),
            min: -300,
            max: 300,
            divisions: 120,
            onChanged: (v) {
              draft.setFeeling(_id(from), _id(to), v.round());
              onChanged();
            },
          ),
        ],
      ),
    );
  }
}

/// Details 8: Your chats together, the 1:1 stats card over this group's
/// chats. Nothing for a group never chatted in.
class EditGroupStatsCard extends StatelessWidget {
  const EditGroupStatsCard({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context) {
    final kit = EditCharacterFormKit(context);
    return CharacterStatsSection(
      characterId: groupId,
      footnote: "From this group's chats.",
      load: (id) async {
        try {
          return await loadGroupStats(liveDatabase(context), id);
        } catch (e) {
          debugPrint('[group stats] load failed: $e');
          return const CharacterStats();
        }
      },
      wrap: (content) => kit.sectionCard(
        icon: Icons.insights_outlined,
        title: 'Your chats together',
        color: AppColors.porchAmberOf(context),
        children: [content],
      ),
    );
  }
}
