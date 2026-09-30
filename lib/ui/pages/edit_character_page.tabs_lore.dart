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
// The character editor's Lorebook tab (with per-entry cards) and
// Worlds tab.
// Extracted verbatim from edit_character_page.dart (god-file campaign,
// Tranche A); `part of` the same library — privates stay in scope.

part of 'edit_character_page.dart';

extension _EditCharacterLoreTabs on _EditCharacterPageState {
  Widget _buildLorebookHeading() {
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

  Widget _lorebookHeaderButton({
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
            ? AppColors.formMasterAccent
            : AppColors.surfaceContainerOf(context),
        foregroundColor: accent
            ? AppColors.onChaosAccent
            : AppColors.textPrimary(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildLorebookTab() {
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
              _buildLorebookHeading(),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    _lorebookHeaderButton(
                      onPressed: _importLorebookJson,
                      icon: Icons.cloud_upload,
                      label: 'Import file',
                    ),
                    _lorebookHeaderButton(
                      onPressed: _exportLorebookJson,
                      icon: Icons.cloud_download,
                      label: 'Export file',
                    ),
                    _lorebookHeaderButton(
                      onPressed: _importLoreFromCharacter,
                      icon: Icons.person_search,
                      label: 'From character',
                    ),
                    _lorebookHeaderButton(
                      onPressed: _addLoreEntry,
                      icon: Icons.add,
                      label: 'Add Entry',
                      accent: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              if (_loreEntries.isEmpty)
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
                          color: AppColors.resolve(
                            context,
                            Colors.white.withValues(alpha: 0.12),
                            Colors.black.withValues(alpha: 0.12),
                          ),
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
                ..._loreEntries.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final lore = entry.value;
                  return _buildLoreCard(idx, lore);
                }),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoreCard(int index, LorebookEntry entry) {
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
              ? AppColors.formMasterAccent.withValues(alpha: 0.15)
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
                onPressed: () => _editLoreEntry(index),
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
                onPressed: () => _removeLoreEntry(index),
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
                        color: AppColors.resolve(
                          context,
                          Colors.white.withValues(alpha: 0.05),
                          Colors.black.withValues(alpha: 0.05),
                        ),
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

  // ═══════════════════════════════════════════════════════════════
  //  TAB 4: WORLDS
  // ═══════════════════════════════════════════════════════════════
}
