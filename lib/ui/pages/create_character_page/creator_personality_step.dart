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
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'create_character_draft.dart';
import 'creator_form_fields.dart';
import 'creator_wizard_chrome.dart';

/// Step 1: description, personality, scenario and the collapsed advanced
/// prompts.
class CreatorPersonalityStep extends StatelessWidget {
  const CreatorPersonalityStep({
    super.key,
    required this.draft,
    required this.onGoToStep,
  });

  final CreateCharacterDraft draft;
  final ValueChanged<int> onGoToStep;

  @override
  Widget build(BuildContext context) {
    return CreatorStepFrame(
      children: [
        const CreatorStepTitle('Personality & World'),
        const SizedBox(height: 8),
        const CreatorStepLead(
          'Define who your character is and the world they inhabit.',
        ),
        const SizedBox(height: 32),

        CreatorExpandableField(
          'Description',
          draft.descriptionController,
          hint: 'Physical appearance, backstory, key traits...',
          maxLines: 4,
        ),
        const SizedBox(height: 20),

        CreatorExpandableField(
          'Personality',
          draft.personalityController,
          hint: 'How they act, speak, think...',
          maxLines: 3,
        ),
        const SizedBox(height: 20),

        CreatorExpandableField(
          'Scenario',
          draft.scenarioController,
          hint: 'The setting, situation, or context...',
          maxLines: 3,
        ),
        const SizedBox(height: 24),

        // Advanced Prompts (collapsed)
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Row(
              children: [
                Icon(
                  Icons.settings_suggest,
                  size: 18,
                  color: AppColors.iconSecondary(context),
                ),
                const SizedBox(width: 8),
                Text(
                  'Advanced Prompts (optional)',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            children: [
              const SizedBox(height: 8),
              CreatorExpandableField(
                'System Prompt',
                draft.systemPromptController,
                hint:
                    'Instructions for the AI about how to play this character...',
                maxLines: 4,
              ),
              const SizedBox(height: 16),
              CreatorExpandableField(
                'Post-History Instructions',
                draft.postHistoryController,
                hint: 'Injected after chat history, before AI response...',
                maxLines: 3,
              ),
            ],
          ),
        ),

        CreatorNavButtons(
          currentStep: 1,
          nameController: draft.nameController,
          onGoToStep: onGoToStep,
        ),
      ],
    );
  }
}
