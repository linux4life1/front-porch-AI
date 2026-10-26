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

import 'package:front_porch_ai/services/storage/settings/appearance_settings.dart';
import 'appearance_choice.dart';

/// Appearance → Scene sound: the switch, and the volume slider that only
/// moves while the switch is on. The sound follows the Ambient scene, so
/// it plays only where a scene is painted.
class SceneSoundControls extends StatelessWidget {
  const SceneSoundControls({super.key, required this.appearance});

  final AppearanceSettings appearance;

  @override
  Widget build(BuildContext context) {
    final on = appearance.sceneSound;
    final volume = appearance.sceneSoundVolume;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const AppearanceCaption('Scene sound'),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              label: 'Scene sound',
              child: Switch(
                key: const ValueKey('appearance-scene-sound'),
                value: on,
                onChanged: appearance.setSceneSound,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 180,
              child: Slider(
                key: const ValueKey('appearance-scene-sound-volume'),
                value: volume,
                label: '${(volume * 100).round()}%',
                semanticFormatterCallback: (v) =>
                    'Scene sound volume ${(v * 100).round()}%',
                onChanged: on ? appearance.setSceneSoundVolume : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
