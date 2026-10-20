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
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/greeting_seed_form.dart';

import 'create_character_draft.dart';
import 'creator_form_fields.dart';
import 'creator_wizard_chrome.dart';

/// Step 2: first message, alternate greetings (each with its realism seed)
/// and example dialogue.
class CreatorDialogueStep extends StatelessWidget {
  const CreatorDialogueStep({
    super.key,
    required this.draft,
    required this.onChanged,
    required this.onGoToStep,
  });

  final CreateCharacterDraft draft;
  final VoidCallback onChanged;
  final ValueChanged<int> onGoToStep;

  @override
  Widget build(BuildContext context) {
    return CreatorStepFrame(
      children: [
        const CreatorStepTitle('Dialogue & Greetings'),
        const SizedBox(height: 8),
        const CreatorStepLead(
          'Configure the character\'s opening message and example dialogue.',
        ),
        const SizedBox(height: 32),

        CreatorExpandableField(
          'First Message',
          draft.firstMessageController,
          hint:
              'The character\'s opening message when a conversation starts...',
          maxLines: 6,
        ),
        const SizedBox(height: 24),

        // Alternate Greetings
        Row(
          children: [
            const CreatorInputLabel('Alternate Greetings', required: false),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                draft.addAltGreeting();
                onChanged();
              },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Greeting'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.formAccentOf(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...draft.altGreetingControllers.asMap().entries.map((entry) {
          final idx = entry.key;
          final ctrl = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: CreatorExpandableField(
                        'Greeting ${idx + 1}',
                        ctrl,
                        hint: 'Alternative opening message...',
                        maxLines: 4,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () {
                        draft.removeAltGreeting(idx);
                        onChanged();
                      },
                      icon: Icon(
                        Icons.remove_circle_outline,
                        color: StatusColors.dangerOf(context),
                        size: 20,
                      ),
                      tooltip: 'Remove greeting',
                    ),
                  ],
                ),
                GreetingSeedForm(
                  seed: draft.altGreetingSeedAt(idx),
                  showNeeds: true,
                  showInventory: true,
                  onChanged: (next) {
                    draft.setAltGreetingSeed(idx, next);
                    onChanged();
                  },
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 20),

        CreatorExpandableField(
          'Example Dialogue',
          draft.exampleDialogueController,
          hint: '<START>\n{{user}}: Hello!\n{{char}}: *smiles warmly*',
          maxLines: 6,
        ),

        CreatorNavButtons(
          currentStep: 2,
          nameController: draft.nameController,
          onGoToStep: onGoToStep,
        ),
      ],
    );
  }
}
