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

part of 'world_management_page.dart';

/// Lorebook section of the create/edit World dialog: header + Add Entry
/// (via [showLorebookEntryDialog]), the empty state, and the entries
/// list (enable/disable, edit, delete). [draft.editingEntries] is the
/// shared edit-session copy (see world_management_page.dialog.dart).
extension _WorldLorebookSection on _WorldManagementPageState {
  /// Copy ticked entries from one character into the place draft.
  /// The character's book is left as it was.
  Future<void> _importLoreFromCharacter(
    BuildContext dialogContext,
    _WorldDraft draft,
    StateSetter setDialogState,
  ) async {
    final repo = Provider.of<CharacterRepository>(dialogContext, listen: false);
    final pick = await showPickCharacterLoreEntriesDialog(
      context: dialogContext,
      characters: repo.characters,
    );
    if (pick == null || pick.entries.isEmpty || !dialogContext.mounted) {
      return;
    }
    setDialogState(() {
      draft.editingEntries.addAll(pick.entries);
    });
  }

  Widget _buildLorebookSection(
    BuildContext ctx,
    _WorldDraft draft,
    StateSetter setDialogState,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.resolve(
          ctx,
          AppColors.surfaceContainer.withValues(alpha: 0.3),
          AppColors.surfaceContainerLight.withValues(alpha: 0.6),
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.borderOf(ctx).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with add button
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(
                  Icons.library_books,
                  size: 18,
                  color: const Color(0xFF10B981),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Lorebook Entries (${draft.editingEntries.length})',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary(ctx),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () =>
                      _importLoreFromCharacter(ctx, draft, setDialogState),
                  icon: const Icon(Icons.person_search, size: 16),
                  label: const Text('From character'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary(ctx),
                    side: BorderSide(color: AppColors.borderOf(ctx)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    textStyle: const TextStyle(fontSize: 12),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    final result = await showLorebookEntryDialog(
                      context: ctx,
                      showEnabled: true,
                    );
                    if (result != null) {
                      setDialogState(() {
                        draft.editingEntries.add(result);
                      });
                    }
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Entry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

          // Entries list
          if (draft.editingEntries.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.resolve(
                    ctx,
                    Colors.white.withValues(alpha: 0.02),
                    AppColors.surfaceContainerLight.withValues(alpha: 0.4),
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.borderOf(ctx).withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.library_books_outlined,
                      size: 32,
                      color: AppColors.textTertiary(ctx),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No lorebook entries yet',
                      style: TextStyle(color: AppColors.textSecondary(ctx)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Add entries to define world lore that will be injected into conversations',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary(ctx),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            ...draft.editingEntries.asMap().entries.map((entry) {
              final int idx = entry.key;
              final e = entry.value;

              return Container(
                margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.resolve(
                    ctx,
                    Colors.white.withValues(alpha: 0.02),
                    AppColors.surfaceContainerLight.withValues(alpha: 0.4),
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    width: 1.5,
                    color: e.enabled
                        ? const Color(0xFF10B981).withValues(alpha: 0.2)
                        : AppColors.borderOf(ctx).withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.displayName,
                            style: TextStyle(
                              color: AppColors.textPrimary(ctx),
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (e.constant)
                          _buildBadge(ctx, 'Always Active', Colors.amberAccent),
                        if (!e.constant)
                          _buildBadge(
                            ctx,
                            'Depth ${e.stickyDepth}',
                            Colors
                                .blueAccent, // theme-keep: lorebook always-on vs enabled 2-state marker (pre-existing, moved verbatim in the god-file split)
                          ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: Icon(
                            e.enabled ? Icons.visibility : Icons.visibility_off,
                            size: 16,
                            color: e.enabled
                                ? const Color(0xFF10B981)
                                : AppColors.textTertiary(ctx),
                          ),
                          tooltip: e.enabled ? 'Disable entry' : 'Enable entry',
                          onPressed: () {
                            setDialogState(() {
                              e.enabled = !e.enabled;
                            });
                          },
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(4),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.edit_outlined,
                            size: 16,
                            color: Colors.white38,
                          ),
                          tooltip: 'Edit entry',
                          onPressed: () async {
                            final result = await showLorebookEntryDialog(
                              context: ctx,
                              existing: e,
                              showEnabled: true,
                            );
                            if (result != null) {
                              setDialogState(() {
                                draft.editingEntries[idx] = result;
                              });
                            }
                          },
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(4),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 16,
                            color: Colors.redAccent,
                          ),
                          tooltip: 'Delete entry',
                          onPressed: () {
                            setDialogState(() {
                              draft.editingEntries.removeAt(idx);
                            });
                          },
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(4),
                        ),
                      ],
                    ),
                    if (e.key.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        e.key,
                        style: TextStyle(
                          color: AppColors.textSecondary(ctx),
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (e.content.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        e.content.length > 150
                            ? '${e.content.substring(0, 150)}...'
                            : e.content,
                        style: TextStyle(
                          color: AppColors.textSecondary(ctx),
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildBadge(BuildContext context, String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
