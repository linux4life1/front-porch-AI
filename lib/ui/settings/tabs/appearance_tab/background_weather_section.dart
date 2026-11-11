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
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'appearance_choice.dart';
import 'scene_sound_controls.dart';

/// Settings → Appearance → Background weather: the story's weather and sky
/// behind the chat (Ambient scene), whether its effects pause while a
/// reply is written, and the scene sound. Shown only while Porch Life's
/// Story Weather is on: with it off no weather can ever paint, so the
/// controls go away and keep their values for when it comes back.
class BackgroundWeatherSection extends StatelessWidget {
  const BackgroundWeatherSection({super.key});

  static const String caption =
      'Only in chats with a world that has climate on. Other chats keep '
      'their plain background.';

  static const String tooltip =
      "The story's weather and sky behind the chat. It shows only in chats "
      'whose character or group has a world with climate turned on and the '
      'story clock running; other chats keep their plain background.';

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    if (!storage.realismSettings.weatherEnabled) {
      return const SizedBox.shrink(key: ValueKey('background-weather-off'));
    }
    final corners = AppCorners.of(context);
    final appearance = storage.appearance;
    return Container(
      key: const ValueKey('background-weather'),
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Flexible(child: SectionHeader('Background weather')),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: tooltip,
                    child: Icon(
                      Icons.info_outline,
                      size: 16,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ],
              ),
              Text(
                'Climate Active',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.formAccentOf(context),
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
        const SizedBox(height: 12),
        Wrap(
          spacing: 28,
          runSpacing: 16,
          children: [
            AppearanceChoice<AmbientScene>(
              key: const ValueKey('appearance-ambient-scene'),
              label: 'Ambient scene',
              values: AmbientScene.values,
              selected: appearance.ambientScene,
              labelOf: (s) => s.label,
              onChanged: appearance.setAmbientScene,
            ),
            // A local model shares the GPU with the stage's moving
            // weather; on by default, it only matters with effects on.
            MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppearanceCaption('Pause effects while generating'),
                  const SizedBox(height: 6),
                  Switch(
                    key: const ValueKey('appearance-ambient-pause'),
                    value: appearance.pauseEffectsWhileGenerating,
                    onChanged: appearance.setPauseEffectsWhileGenerating,
                  ),
                ],
              ),
            ),
            // Rain, wind, birds or crickets for the scene, thunder after
            // a storm's flash; off by default.
              SceneSoundControls(appearance: appearance),
            ],
          ),
        ],
      ),
    );
  }
}
