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
import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_lore_card.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section/realism_form_section.dart';

/// The character editor's Lorebook tab. The page owns the entry list and the
/// import / export / add / edit / remove actions; this tab only lays them out.
class EditCharacterLorebookTab extends StatelessWidget {
  final List<LorebookEntry> entries;
  final VoidCallback onImportFile;
  final VoidCallback onExportFile;
  final VoidCallback onImportFromCharacter;
  final VoidCallback onAddEntry;
  final void Function(int index) onEditEntry;
  final void Function(int index) onRemoveEntry;

  /// Called after an entry's enable switch flips it in place.
  final VoidCallback onChanged;

  /// A group member's editor: when the group reads this lorebook.
  final String? memberNote;

  const EditCharacterLorebookTab({
    super.key,
    required this.entries,
    required this.onImportFile,
    required this.onExportFile,
    required this.onImportFromCharacter,
    required this.onAddEntry,
    required this.onEditEntry,
    required this.onRemoveEntry,
    required this.onChanged,
    this.memberNote,
  });

  Widget _heading(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Lorebook',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'World lore entries inject context when keywords are detected.',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary(context),
          ),
        ),
      ],
    );
  }

  Widget _headerButton(
    BuildContext context, {
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    bool accent = false,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: accent
            ? AppColors.formAccentOf(context)
            : AppColors.surfaceContainerOf(context),
        foregroundColor: accent
            ? AppColors.onAccentOf(context)
            : AppColors.textPrimary(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header. The editor column is 720px wide and three actions
              // already fill the row beside the title, so Export sits with
              // them on the next line instead of crushing the heading.
              _heading(context),
              const SizedBox(height: 12),
              if (memberNote != null) MemberEditorNote(memberNote!),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    _headerButton(
                      context,
                      onPressed: onImportFile,
                      icon: Icons.cloud_upload,
                      label: 'Import file',
                    ),
                    _headerButton(
                      context,
                      onPressed: onExportFile,
                      icon: Icons.cloud_download,
                      label: 'Export file',
                    ),
                    _headerButton(
                      context,
                      onPressed: onImportFromCharacter,
                      icon: Icons.person_search,
                      label: 'From character',
                    ),
                    _headerButton(
                      context,
                      onPressed: onAddEntry,
                      icon: Icons.add,
                      label: 'Add Entry',
                      accent: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              if (entries.isEmpty)
                Container(
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: AppColors.cardOf(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.borderOf(
                        context,
                      ).withValues(alpha: 0.45),
                    ),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.menu_book_outlined,
                          size: 48,
                          color: InkColors.washOf(context, 0.12, 0.12),
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
                          'Add entries to inject context-aware world lore.',
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
                ...entries.asMap().entries.map((entry) {
                  final idx = entry.key;
                  return EditCharacterLoreCard(
                    entry: entry.value,
                    onEdit: () => onEditEntry(idx),
                    onRemove: () => onRemoveEntry(idx),
                    onChanged: onChanged,
                  );
                }),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}
