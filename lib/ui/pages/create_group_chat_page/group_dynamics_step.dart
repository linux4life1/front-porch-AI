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
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/relationship_scale.dart'
    show relationshipTierName, relationshipScaleColor;

import 'create_group_chat_page.dart';

// Relationship tier-name + valence color are shared with the group editor
// (relationshipTierName / relationshipScaleColor in
// group_realism_dynamics_editor.dart) so both surfaces label + color a hidden
// feeling score identically — one UX standard, no duplicated logic.

/// Shown in place of Group Dynamics for groups larger than 4. The page wraps
/// it in a [Center], as before.
class GroupDynamicsDisabledNotice extends StatelessWidget {
  const GroupDynamicsDisabledNotice({super.key, required this.memberCount});

  final int memberCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.people_alt,
            size: 64,
            color: AppColors.textTertiary(context),
          ),
          const SizedBox(height: 16),
          Text(
            'Group Dynamics',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Intra-group relationship seeding is only available for groups with 4 or fewer members.\n\n'
            'Your current group has $memberCount members.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
          const SizedBox(height: 24),
          Text(
            'Larger groups use different social dynamics modeling.',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

/// Intra-group relationship seeding, shown inside the Realism step. Only
/// built when the roster is 4 or fewer.
class GroupDynamicsStep extends StatelessWidget {
  const GroupDynamicsStep({
    super.key,
    required this.draft,
    required this.actions,
    this.showNav = true,
  });

  final GroupWizardDraft draft;
  final GroupWizardActions actions;

  /// False when another step hosts this one and owns the nav buttons.
  final bool showNav;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Group Dynamics',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary(context),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message:
                  'Pre-seed hidden intra-group relationship scores (same -300..+300 raw scale as Long-Term Bond in Realism). Only available for groups of 4 or fewer per engine limits. These private feelings (never shown in UI) influence how members treat each other in prompts and behavior when the Realism Engine is active. Values persist in the Group Card export and round-trip on split-to-solo.',
              preferBelow: false,
              child: Icon(
                Icons.info_outline,
                size: 18,
                color: AppColors.textTertiary(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Pre-seed how the characters feel toward each other. These hidden relationships influence behavior in small groups (4 or fewer members).',
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
        const SizedBox(height: 24),

        ...draft.members.map((source) => _sourceCard(context, source)),

        const SizedBox(height: 16),
        Text(
          'These values are private to the group and affect how characters treat each other when Realism is active.',
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 12,
          ),
        ),

        if (showNav)
          GroupWizardNavButtons(
            draft: draft,
            actions: actions,
            currentStep: GroupWizardSteps.realism,
          ),
      ],
    );
  }

  Widget _sourceCard(BuildContext context, CharacterCard source) {
    final sourceId = draft.stableId(source);
    final relationships =
        (draft.memberRealismSeeds[sourceId]?['relationships'] as Map?)
            ?.cast<String, int>() ??
        {};

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                groupMemberAvatar(context, source, radius: 20),
                const SizedBox(width: 12),
                Text(
                  'How ${source.name} feels about others',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            ...draft.members
                .where((target) => draft.stableId(target) != sourceId)
                .map(
                  (target) => _targetRow(
                    context,
                    source,
                    target,
                    relationships[draft.stableId(target)] ?? 0,
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _targetRow(
    BuildContext context,
    CharacterCard source,
    CharacterCard target,
    int currentValue,
  ) {
    final sourceId = draft.stableId(source);
    final targetId = draft.stableId(target);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              groupMemberAvatar(context, target, radius: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(target.name)),
              Tooltip(
                message:
                    'Hidden relationship score on the same -300..+300 scale as Long-Term Bond. Positive values mean the source character privately feels warmly toward the target.',
                child: Text(
                  currentValue > 0 ? '+$currentValue' : currentValue.toString(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: relationshipScaleColor(context, currentValue),
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: relationshipScaleColor(context, currentValue),
              inactiveTrackColor: AppColors.borderOf(
                context,
              ).withValues(alpha: 0.3),
              thumbColor: relationshipScaleColor(context, currentValue),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: currentValue.toDouble().clamp(-300, 300),
              min: -300,
              max: 300,
              divisions: 120,
              label: currentValue.toString(),
              onChanged: (v) {
                draft.updateRelationship(sourceId, targetId, v.round());
              },
            ),
          ),
          const SizedBox(height: 4),
          Tooltip(
            message:
                'Starting hidden feeling of ${source.name} toward ${target.name}. Matches the Long-Term Bond tier system used in the 1:1 Realism creator and runtime evaluations. These scores only affect groups of 4 or fewer and drive realistic intra-group behavior when Realism is enabled.',
            child: Text(
              relationshipTierName(currentValue),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: relationshipScaleColor(context, currentValue),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
