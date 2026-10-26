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

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/storage/settings/appearance_settings.dart';
import 'appearance_choice.dart';

/// Appearance → Scene sound: the switch, and the volume slider that only
/// moves while the switch is on. The sound follows the Ambient scene, so
/// it plays where a scene is painted. A drag is held here and written once
/// when it ends, so dragging does not write the setting (and wake every
/// listener) per pixel; the loop moves to the new volume then.
class SceneSoundControls extends StatefulWidget {
  const SceneSoundControls({super.key, required this.appearance});

  final AppearanceSettings appearance;

  @override
  State<SceneSoundControls> createState() => _SceneSoundControlsState();
}

class _SceneSoundControlsState extends State<SceneSoundControls> {
  /// The slider's value mid-drag; null when not dragging.
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final appearance = widget.appearance;
    final on = appearance.sceneSound;
    final volume = _drag ?? appearance.sceneSoundVolume;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const AppearanceCaption('Scene sound'),
        const SizedBox(height: 6),
        // The switch and the slider share a row where the column has room
        // for both. The sidebar leaves a 400 px window about 126 px here,
        // so the slider drops under the switch and takes the width there
        // is, up to 180 px, instead of the row spilling past the edge or
        // the slider shrinking to a sliver nobody can set.
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              label: 'Scene sound',
              child: Switch(
                key: const ValueKey('appearance-scene-sound'),
                value: on,
                onChanged: appearance.setSceneSound,
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Slider(
                key: const ValueKey('appearance-scene-sound-volume'),
                value: volume,
                label: '${(volume * 100).round()}%',
                semanticFormatterCallback: (v) =>
                    'Scene sound volume ${(v * 100).round()}%',
                onChanged: on ? (v) => setState(() => _drag = v) : null,
                onChangeEnd: on ? _commit : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _commit(double value) {
    setState(() => _drag = null);
    unawaited(
      widget.appearance.setSceneSoundVolume(value).catchError((
        Object e,
        StackTrace st,
      ) {
        debugPrint('Scene sound: could not save the volume: $e\n$st');
      }),
    );
  }
}
