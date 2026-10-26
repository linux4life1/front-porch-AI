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
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/scene/scene_resolver.dart';
import 'ambient_stage.dart';
import 'scene_sound_host.dart';

/// The Ambient Stage as the chat surface mounts it: the story's weather
/// over whatever background won, behind the chat column, and its sound
/// (docs/design/ambient-stage.md). A child of the backdrop's Stack.
///
/// Mounted only while there is a scene, so Ambient scene Off, a chat with
/// no weather and a closed chat paint and play nothing. Rebuilds only when
/// the tokens, the generating flag or the Scene sound setting change, not
/// per streamed token. Generating covers the settling post-gen passes too,
/// which still call the model after isGenerating drops; StorageService
/// carries the appearance settings. Reduce motion makes the stage static,
/// its weather held still (and a still stage fires no flash, so no
/// thunder either).
class AmbientStageMount extends StatelessWidget {
  const AmbientStageMount({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector2<
      ChatService,
      StorageService,
      (SceneTokens?, bool generating, bool sound, double volume)
    >(
      selector: (_, chat, storage) => (
        sceneTokensFor(chat),
        chat.isGenerating || chat.isSettlingTurn,
        storage.appearance.sceneSound,
        storage.appearance.sceneSoundVolume,
      ),
      builder: (context, scene, _) {
        final (tokens, generating, sound, volume) = scene;
        if (tokens == null) return const SizedBox.shrink();
        return Positioned.fill(
          child: IgnorePointer(
            child: SceneSoundHost(
              tokens: tokens,
              enabled: sound,
              volume: volume,
              builder: (context, onFlash) => AmbientStage(
                tokens: tokens,
                animated:
                    tokens.hasEffects &&
                    !MediaQuery.disableAnimationsOf(context),
                generating: generating,
                onFlash: onFlash,
              ),
            ),
          ),
        );
      },
    );
  }
}
