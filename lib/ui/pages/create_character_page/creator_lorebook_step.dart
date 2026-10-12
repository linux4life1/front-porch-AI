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
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'create_character_draft.dart';
import 'creator_form_fields.dart';
import 'creator_lorebook_entry_card.dart';
import 'creator_wizard_chrome.dart';

/// Step 3: the card's lorebook — add, edit, toggle and delete entries.
class CreatorLorebookStep extends StatelessWidget {
  const CreatorLorebookStep({
    super.key,
    required this.draft,
    required this.onChanged,
    required this.onGoToStep,
  });

  final CreateCharacterDraft draft;
  final VoidCallback onChanged;
  final ValueChanged<int> onGoToStep;

  void _commit() {
    draft.updateTokenEstimate();
    onChanged();
  }

  Future<void> _addLorebookEntry(BuildContext context) async {
    final result = await showLorebookEntryDialog(context: context);
    if (result != null) {
      draft.lorebookEntries.add(result);
      _commit();
    }
  }

  Future<void> _editLorebookEntry(BuildContext context, int index) async {
    final entry = draft.lorebookEntries[index];
    final result = await showLorebookEntryDialog(
      context: context,
      existing: entry,
      showEnabled: true,
    );
    if (result != null) {
      draft.lorebookEntries[index] = result;
      _commit();
    }
  }

  void _deleteLorebookEntry(int index) {
    draft.lorebookEntries.removeAt(index);
    _commit();
  }

  @override
  Widget build(BuildContext context) {
    return CreatorStepFrame(
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CreatorStepTitle('Lorebook'),
                  SizedBox(height: 8),
                  CreatorStepLead(
                    'Add world lore entries that inject context into conversations when keywords are detected.',
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              onPressed: () => _addLorebookEntry(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Entry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.formMasterAccent,
                foregroundColor: AppColors.onChaosAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        if (draft.lorebookEntries.isEmpty)
          Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: AppColors.cardOf(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.borderOf(context).withValues(alpha: 0.45),
              ),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.menu_book_outlined,
                    size: 48,
                    color: AppColors.hairlineOf(context, 0.15),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No lorebook entries yet',
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Add entries to inject context-aware world lore into conversations.',
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...draft.lorebookEntries.asMap().entries.map((entry) {
            final idx = entry.key;
            final lore = entry.value;
            return CreatorLorebookEntryCard(
              entry: lore,
              onEnabledChanged: (val) {
                lore.enabled = val;
                _commit();
              },
              onEdit: () => _editLorebookEntry(context, idx),
              onDelete: () => _deleteLorebookEntry(idx),
            );
          }),

        CreatorNavButtons(
          currentStep: 3,
          nameController: draft.nameController,
          onGoToStep: onGoToStep,
        ),
      ],
    );
  }
}
