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

/// "The Engine" group — extracted when the tab grew past its comfort size
/// (it once also held the Model transport card, since moved to Generation
/// settings on both surfaces).
class PorchLifeEngineCard extends StatelessWidget {
  const PorchLifeEngineCard({
    super.key,
    required this.engineOn,
    required this.storage,
    required this.chat,
  });

  final bool engineOn;
  final StorageService storage;
  final ChatService chat;

  @override
  Widget build(BuildContext context) {
    return FeatureGroupCard(
      title: 'The Engine',
      subtitle: 'feelings about what you do',
      rows: [
        FeatureRow(
          icon: Icons.theater_comedy,
          label: 'Realism Engine',
          need: FeatureNeed.core,
          blurb:
              'Bond and trust, moods that carry between turns, physical '
              'state — how the character feels about what you just did. '
              'Needs, the story clock and desire all read from it; the '
              'rest of Porch Life runs with or without it, and every row '
              'says which it is.',
          value: engineOn,
          onChanged: (v) {
            storage.setRealismDefault(v);
            chat.setRealismEnabled(v);
          },
        ),
        FeatureRow(
          icon: Icons.favorite_outline,
          label: 'Needs',
          need: FeatureNeed.needs,
          dependsOn: 'the Realism Engine',
          satisfied: engineOn,
          blurb:
              'Hunger, energy, comfort and the rest, Sims-style — they '
              'drift through a scene and colour how the character feels. '
              'The engine is what turns a need into a mood, so needs run '
              'with it or not at all. Individual chats can still switch '
              'them off in the sidebar.',
          value: storage.needsSimDefault,
          onChanged: (v) {
            storage.realismSettings.setNeedsSimDefault(v);
            chat.setNeedsSimEnabled(v);
          },
        ),
      ],
    );
  }
}
