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
import 'package:front_porch_ai/ui/avatar_creation/avatar_generation_panel.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'creator_form_fields.dart';

/// Step 6: Portrait & Avatars — the shared AvatarGenerationPanel, entered
/// holding the freshly saved [card] so nothing here can lose the writing.
class CreatorPortraitStep extends StatelessWidget {
  const CreatorPortraitStep({
    super.key,
    required this.card,
    required this.description,
    this.existingPortraitPath,
    required this.panelBusy,
    required this.onBusyChanged,
    required this.onDone,
  });

  final CharacterCard card;

  /// The wizard's description text, seeding the portrait prompt.
  final String description;

  /// The persona picture the card was saved with, if it came from one.
  final String? existingPortraitPath;

  /// The panel is mid-generation — Done is locked so leaving can't silently
  /// drop work the engine is still finishing.
  final bool panelBusy;
  final ValueChanged<bool> onBusyChanged;
  final VoidCallback onDone;

  /// Portrait-prompt seed from the wizard's own fields: the description (the
  /// manual creator's appearance lives there), macros resolved to the name.
  String _portraitPromptSeed(String name) {
    var seed = description
        .replaceAll('{{char}}', name)
        .replaceAll('{{user}}', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (seed.length > 400) seed = seed.substring(0, 400);
    if (seed.isEmpty) seed = 'character portrait of $name';
    return seed;
  }

  @override
  Widget build(BuildContext context) {
    return CreatorStepFrame(
      children: [
        const CreatorStepTitle('Portrait & Avatars'),
        const SizedBox(height: 10),
        // The saved chip — nothing below can lose the writing.
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.logReady.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: AppColors.logReady.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              '✓ ${card.name} is saved — everything below is optional '
              'and can\'t lose your writing',
              style: const TextStyle(color: AppColors.logReady, fontSize: 11.5),
            ),
          ),
        ),
        const SizedBox(height: 20),
        AvatarGenerationPanel(
          key: ValueKey(card.dbId),
          card: card,
          ensureCardSaved: () async => card,
          initialPrompt: _portraitPromptSeed(card.name),
          existingPortraitPath: existingPortraitPath,
          onBusyChanged: onBusyChanged,
        ),
        const SizedBox(height: 24),
        Center(
          child: SizedBox(
            width: 280,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: panelBusy ? null : onDone,
              icon: const Icon(Icons.check, size: 20),
              label: const Text('Done', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.porchAmberOf(context),
                foregroundColor: AppColors.onChaosAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
