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
//
// Manual creator: the Lorebook step, its per-entry cards, and the
// add/edit/delete entry actions.
// Extracted verbatim from create_character_page.dart (god-file campaign,
// Tranche A); `part of` the same library, so privates and the mandatory
// step-indicator wizard flow are unchanged.

part of 'create_character_page.dart';

extension _CreateCharacterLorebookStep on _CreateCharacterPageState {
  Widget _buildLorebookStep() {
    return Center(
      key: const ValueKey('lorebook'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lorebook',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add world lore entries that inject context into conversations when keywords are detected.',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary(context),
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _addLorebookEntry,
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

              if (_lorebookEntries.isEmpty)
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
                ..._lorebookEntries.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final lore = entry.value;
                  return _buildLorebookEntryCard(idx, lore);
                }),

              _buildNavButtons(currentStep: 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLorebookEntryCard(int index, LorebookEntry entry) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          width: 1.5,
          color: entry.constant
              ? AppColors.porchAmberOf(context).withValues(alpha: 0.3)
              : entry.enabled
              ? AppColors.formMasterAccent.withValues(alpha: 0.2)
              : AppColors.borderOf(context).withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.menu_book,
                size: 14,
                color: entry.constant
                    ? AppColors.porchAmberOf(context)
                    : entry.enabled
                    ? AppColors.formMasterAccent
                    : AppColors.textTertiary(context),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  entry.displayName,
                  style: TextStyle(
                    color: entry.enabled
                        ? AppColors.textPrimary(context)
                        : AppColors.textTertiary(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              if (entry.constant)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.porchAmberOf(
                      context,
                    ).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Always Active',
                    style: TextStyle(
                      color: AppColors.porchAmberOf(context),
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (!entry.constant)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.formMasterAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Depth ${entry.stickyDepth}',
                    style: const TextStyle(
                      color: AppColors.formMasterAccent,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              Tooltip(
                message: entry.enabled
                    ? 'Disable — entry won\'t be matched'
                    : 'Enable — entry will match on its keys',
                child: Switch(
                  value: entry.enabled,
                  onChanged: (val) {
                    rebuildState(() {
                      entry.enabled = val;
                      _updateTokenEstimate();
                    });
                  },
                  activeTrackColor: AppColors.formMasterAccent.withValues(
                    alpha: 0.5,
                  ),
                  activeThumbColor: AppColors.formMasterAccent,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              IconButton(
                onPressed: () => _editLorebookEntry(index),
                icon: Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: AppColors.textTertiary(context),
                ),
                tooltip: 'Edit entry',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),
              IconButton(
                onPressed: () => _deleteLorebookEntry(index),
                icon: Icon(
                  Icons.delete_outline,
                  size: 16,
                  color: AppColors.negativeAccentOf(context),
                ),
                tooltip: 'Delete entry',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),
            ],
          ),
          if (entry.key.isNotEmpty && !entry.constant) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 3,
              children: entry.keys
                  .map(
                    (k) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.hairlineOf(context, 0.05),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        k.trim(),
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 10,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _addLorebookEntry() async {
    final result = await showLorebookEntryDialog(context: context);
    if (result != null) {
      rebuildState(() {
        _lorebookEntries.add(result);
        _updateTokenEstimate();
      });
    }
  }

  Future<void> _editLorebookEntry(int index) async {
    final entry = _lorebookEntries[index];
    final result = await showLorebookEntryDialog(
      context: context,
      existing: entry,
      showEnabled: true,
    );
    if (result != null) {
      rebuildState(() {
        _lorebookEntries[index] = result;
        _updateTokenEstimate();
      });
    }
  }

  void _deleteLorebookEntry(int index) {
    rebuildState(() {
      _lorebookEntries.removeAt(index);
      _updateTokenEstimate();
    });
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 4: REALISM ENGINE
  // ═══════════════════════════════════════════════════════════════
}
