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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'appearance_choice.dart';

/// Settings → Appearance → Chat Appearance → Mood on the character: each
/// character's mood, bond, trust and needs painted on their portrait,
/// needs bars and bubbles, with a Drama slider that only moves while the
/// row is on (as the volume does with Scene sound). Shown only while Porch
/// Life's Realism Engine is on: with it off there is no mood to paint, so
/// the row goes away and keeps its values for when it comes back.
class MoodOnCharacterControls extends StatelessWidget {
  const MoodOnCharacterControls({super.key});

  static const String caption =
      "Each character's mood on their portrait and needs bars, in their own "
      'Realism colours. Needs Realism on for the chat.';

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    if (!storage.realismSettings.realismAllowed) {
      return const SizedBox.shrink(key: ValueKey('mood-on-character-off'));
    }
    final corners = AppCorners.of(context);
    final appearance = storage.appearance;
    final on = appearance.moodOnCharacter.portraitOn;
    return Container(
      key: const ValueKey('mood-on-character'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: corners.circular(12),
        border: Border.all(
          color: AppColors.borderOf(context),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'REALISM MOOD',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.textSecondary(context),
                ),
              ),
              Text(
                'Realism Active',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.verifiedAccentOf(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 28,
            runSpacing: 16,
            children: [
            AppearanceChoice<MoodOnCharacter>(
              key: const ValueKey('appearance-mood-on-character'),
              label: 'Mood on the character',
              values: MoodOnCharacter.values,
              selected: appearance.moodOnCharacter,
              labelOf: (s) => s.label,
              onChanged: appearance.setMoodOnCharacter,
            ),
            MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppearanceCaption('Drama'),
                  SizedBox(
                    width: 180,
                    child: Slider(
                      key: const ValueKey('appearance-mood-drama'),
                      value: appearance.moodDrama,
                      min: kMoodDramaMin,
                      max: kMoodDramaMax,
                      divisions: 12,
                      label: appearance.moodDrama.toStringAsFixed(1),
                      onChanged: on ? appearance.setMoodDrama : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          caption,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary(context),
          ),
        ),
      ],
    ),
  );
  }
}
