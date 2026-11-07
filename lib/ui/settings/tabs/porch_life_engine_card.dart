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
import 'package:front_porch_ai/ui/settings/existing_chats_offer_dialog.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// "The Engine" group — extracted when the tab grew past its comfort size
/// (it once also held the Model transport card, since moved to Generation
/// settings on both surfaces).
///
/// The Realism Engine row is the permission ([engineOn] is
/// `realismAllowed`): off, no chat runs Realism and each chat keeps its own
/// switch. Under it, "Start every new chat with Realism" is the old
/// `realismDefault` switch with the name of what it does.
class PorchLifeEngineCard extends StatelessWidget {
  const PorchLifeEngineCard({
    super.key,
    required this.engineOn,
    required this.storage,
  });

  final bool engineOn;
  final StorageService storage;

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
              'Allows bond and trust, moods that carry between turns, '
              'physical state — how the character feels about what you just '
              'did. Needs and desire read from it; the rest of Porch Life '
              'runs with or without it, and every row says which it is. '
              'Off: no chat runs the engine, and Needs and Afterglow stop '
              'with it. Each chat keeps its own choice for when you turn '
              'this back on.',
          value: engineOn,
          onChanged: (v) async {
            final was = storage.realismSettings.realismAllowed;
            await storage.realismSettings.setRealismAllowed(v);
            if (!context.mounted) return;
            await offerRealismInExistingChats(context, wasAllowed: was);
          },
          child: _StartWithRealismRow(storage: storage),
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
          value: storage.realismSettings.needsSimDefault,
          onChanged: (v) async {
            final was = storage.realismSettings.needsSimDefault;
            await storage.realismSettings.setNeedsSimDefault(v);
            if (!context.mounted) return;
            await offerNeedsInExistingChats(context, wasAllowed: was);
          },
          showChildWhenOff: true,
          child: storage.realismSettings.passageOfTimeDefault
              ? null
              : const NeedsClockOffNote(
                  clockOn: false,
                  padding: EdgeInsets.zero,
                ),
        ),
      ],
    );
  }
}

/// "Start every new chat with Realism", nested under the permission:
/// `realismDefault`, the OR every new 1:1 chat's switch is seeded with.
class _StartWithRealismRow extends StatelessWidget {
  const _StartWithRealismRow({required this.storage});

  final StorageService storage;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Start every new chat with Realism',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 2),
              Text(
                "Even when the character's card doesn't turn it on, such as "
                'an imported card. Chats you already have keep their own '
                'switch.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch(
          value: storage.realismSettings.realismDefault,
          onChanged: storage.realismSettings.setRealismDefault,
        ),
      ],
    );
  }
}
