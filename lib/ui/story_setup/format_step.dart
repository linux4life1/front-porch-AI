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
// but WITHOUT ANY WARRANTY, without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/story_setup/setup_widgets.dart';
import 'package:front_porch_ai/ui/story_setup/story_setup_draft.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Wizard step: the story's shape — length, pacing, dialogue density, act
/// count, and maturity rating.
class FormatStep extends StatelessWidget {
  final StorySetupDraft draft;
  final VoidCallback onChanged;

  const FormatStep({super.key, required this.draft, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SetupSectionHeader('Prose Length', Icons.format_size),
        const SizedBox(height: 10),
        ...storyProseLengths.entries.map(
          (e) => SetupRadioTile(
            e.key,
            e.value,
            selected: draft.proseLength == e.key,
            onTap: () {
              draft.proseLength = e.key;
              onChanged();
            },
          ),
        ),
        const SizedBox(height: 20),
        const SetupSectionHeader('Narrative Pace', Icons.speed),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: storyPaceOptions.entries
              .map(
                (e) => SetupRadioChip(
                  e.key,
                  selected: draft.narrativePace == e.key,
                  subtitle: e.value,
                  onTap: () {
                    draft.narrativePace = e.key;
                    onChanged();
                  },
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 20),
        const SetupSectionHeader('Dialogue Density', Icons.chat_bubble_outline),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: storyDialogueOptions.entries
              .map(
                (e) => SetupRadioChip(
                  e.key,
                  selected: draft.dialogueDensity == e.key,
                  subtitle: e.value,
                  onTap: () {
                    draft.dialogueDensity = e.key;
                    onChanged();
                  },
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 28),
        const SetupSectionHeader('Story Structure', Icons.account_tree),
        const SizedBox(height: 12),
        _buildActCountSlider(context),
        const SizedBox(height: 20),
        const SetupSectionHeader('Maturity Rating', Icons.shield_outlined),
        const SizedBox(height: 10),
        ...storyMaturityOptions.entries.map(
          (e) => SetupRadioTile(
            e.key,
            e.value,
            selected: draft.maturityRating == e.key,
            onTap: () {
              draft.maturityRating = e.key;
              onChanged();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildActCountSlider(BuildContext context) {
    final accent = AppColors.porchHoneyOf(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.borderOf(context).withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Number of Acts',
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${draft.actCount}',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: accent,
              inactiveTrackColor: AppColors.borderOf(
                context,
              ).withValues(alpha: 0.4),
              thumbColor: accent,
              overlayColor: accent.withValues(alpha: 0.2),
              valueIndicatorColor: accent,
            ),
            child: Slider(
              value: draft.actCount.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              label: '${draft.actCount} acts',
              onChanged: (v) {
                draft.actCount = v.round();
                onChanged();
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final label in const [
                '1 (Short story)',
                '3 (Classic)',
                '5 (Epic)',
              ])
                Text(
                  label,
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
