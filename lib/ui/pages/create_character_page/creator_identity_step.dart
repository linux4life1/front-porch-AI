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

/// Step 0: name and tags.
class CreatorIdentityStep extends StatelessWidget {
  const CreatorIdentityStep({
    super.key,
    required this.draft,
    required this.onChanged,
    required this.onGoToStep,
  });

  final CreateCharacterDraft draft;
  final VoidCallback onChanged;
  final ValueChanged<int> onGoToStep;

  void _addTag(String value) {
    final tag = value.trim();
    if (tag.isNotEmpty && !draft.tags.contains(tag)) {
      draft.tags.add(tag);
      onChanged();
      draft.tagController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CreatorStepFrame(
      children: [
        const CreatorStepTitle('Character Identity'),
        const SizedBox(height: 8),
        const CreatorStepLead(
          'Set your character\'s name and tags. Portrait and avatars '
          'come in the final step, after your writing is safely saved.',
        ),
        const SizedBox(height: 32),

        // Name field
        const CreatorInputLabel('Character Name', required: true),
        const SizedBox(height: 8),
        TextFormField(
          controller: draft.nameController,
          style: TextStyle(color: AppColors.textPrimary(context), fontSize: 16),
          decoration: creatorInputDecoration(context, 'Enter character name'),
        ),
        const SizedBox(height: 24),

        // Tags
        const CreatorInputLabel('Tags', required: false),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...draft.tags.map(
              (tag) => Chip(
                label: Text(
                  tag,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 12,
                  ),
                ),
                backgroundColor: AppColors.surfaceContainerOf(context),
                side: BorderSide.none,
                deleteIcon: Icon(
                  Icons.close,
                  size: 14,
                  color: AppColors.iconSecondary(context),
                ),
                onDeleted: () {
                  draft.tags.remove(tag);
                  onChanged();
                },
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: draft.tagController,
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 14,
                ),
                decoration: creatorInputDecoration(context, 'Add a tag...'),
                onSubmitted: _addTag,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => _addTag(draft.tagController.text),
              icon: Icon(
                Icons.add_circle,
                color: AppColors.formAccentOf(context),
              ),
              tooltip: 'Add tag',
            ),
          ],
        ),

        CreatorNavButtons(
          currentStep: 0,
          nameController: draft.nameController,
          onGoToStep: onGoToStep,
        ),
      ],
    );
  }
}
