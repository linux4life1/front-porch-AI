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
import 'package:front_porch_ai/services/world_chain.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Shown on the Lore & Worlds tab when the stored group lorebook can't be read.
const kEditGroupUnreadableLoreNote =
    "This group's lorebook couldn't be read, so its entries aren't being "
    'used. New entries you add here can replace it; Save asks first.';

/// Lore & Worlds tab of the group editor: the group lorebook (add/edit/delete
/// entries), the "inherit character & world lorebooks" toggle, and the Linked
/// Places (worlds) chip picker. Edits go out through the callbacks; the page
/// owns the lists.
class EditGroupLoreWorldsTab extends StatelessWidget {
  const EditGroupLoreWorldsTab({
    super.key,
    required this.allWorlds,
    required this.loreEntries,
    required this.bookUnreadable,
    required this.inheritCharacterLorebooks,
    required this.worldIds,
    required this.onAddEntry,
    required this.onReplaceEntry,
    required this.onRemoveEntry,
    required this.onInheritChanged,
    required this.onLinkWorld,
    required this.onUnlinkWorld,
  });

  /// Every place world (`WorldRepository.placeWorlds`). Chips name what is
  /// linked; the Link World picker offers only the top-level ones.
  final List<World> allWorlds;

  World? _worldById(String id) {
    for (final w in allWorlds) {
      if (w.id == id) return w;
    }
    return null;
  }

  final List<LorebookEntry> loreEntries;
  final bool bookUnreadable;
  final bool inheritCharacterLorebooks;
  final List<String> worldIds;
  final ValueChanged<LorebookEntry> onAddEntry;
  final void Function(int index, LorebookEntry entry) onReplaceEntry;
  final ValueChanged<int> onRemoveEntry;
  final ValueChanged<bool> onInheritChanged;
  final ValueChanged<String> onLinkWorld;
  final ValueChanged<String> onUnlinkWorld;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Group Lorebook',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary(context),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final added = await showLorebookEntryDialog(
                    context: context,
                    showEnabled: true,
                  );
                  if (added != null) onAddEntry(added);
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Entry'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (bookUnreadable)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                kEditGroupUnreadableLoreNote,
                style: TextStyle(color: AppColors.porchAmberOf(context)),
              ),
            ),
          if (loreEntries.isEmpty)
            Text(
              'No group lore entries yet. These take highest priority in prompts.',
              style: TextStyle(color: AppColors.textSecondary(context)),
            )
          else
            ...loreEntries.asMap().entries.map((e) {
              final i = e.key;
              final entry = e.value;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  entry.name.isNotEmpty ? entry.name : entry.key,
                  style: TextStyle(color: AppColors.textPrimary(context)),
                ),
                subtitle: Text(
                  entry.content.length > 80
                      ? '${entry.content.substring(0, 80)}...'
                      : entry.content,
                  style: TextStyle(color: AppColors.textSecondary(context)),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      // The shared editor edits a clone, so imported
                      // advanced fields survive and Cancel asks first.
                      onPressed: () async {
                        final edited = await showLorebookEntryDialog(
                          context: context,
                          existing: entry,
                          showEnabled: true,
                        );
                        if (edited != null) onReplaceEntry(i, edited);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, size: 20),
                      onPressed: () => onRemoveEntry(i),
                    ),
                  ],
                ),
              );
            }),

          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Inherit character & world lorebooks'),
            subtitle: const Text(
              'When on, member cards and their attached worlds contribute lore in addition to the group lorebook above.',
            ),
            value: inheritCharacterLorebooks,
            onChanged: onInheritChanged,
          ),

          const SizedBox(height: 20),
          Text(
            'Linked Worlds',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Template for new chats of this group (climate + world lore). '
            'Chats start at each world\'s starred place.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary(context),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ...worldIds.map((wid) {
                final w = allWorlds.firstWhere(
                  (ww) => ww.id == wid || ww.name == wid,
                  orElse: () => World(
                    name: wid,
                    lorebook: Lorebook(entries: const []),
                  ),
                );
                final isMissing = !allWorlds.any(
                  (ww) => ww.id == wid || ww.name == wid,
                );
                return Chip(
                  label: Text(
                    isMissing ? '$wid (missing)' : w.name,
                    style: TextStyle(
                      color: isMissing ? AppColors.textTertiary(context) : null,
                    ),
                  ),
                  onDeleted: () => onUnlinkWorld(wid),
                );
              }),
              OutlinedButton.icon(
                onPressed: () async {
                  final chosen = await showDialog<World>(
                    context: context,
                    builder: (ctx) => SimpleDialog(
                      backgroundColor: AppColors.surfaceOf(context),
                      title: const Text('Link a World'),
                      children: linkableWorldsOf(allWorlds, _worldById)
                          .map(
                            (w) => SimpleDialogOption(
                              onPressed: () => Navigator.pop(ctx, w),
                              child: Text(
                                w.biomeId != null && w.biomeId != 'temperate'
                                    ? '${w.name} (${w.biomeId})'
                                    : w.name,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  );
                  if (chosen != null &&
                      !worldIds.contains(chosen.id) &&
                      !worldIds.contains(chosen.name)) {
                    onLinkWorld(chosen.id);
                  }
                },
                icon: const Icon(Icons.public, size: 18),
                label: const Text('Link World'),
              ),
            ],
          ),

          const SizedBox(height: 24),
          // Chaos Mode flags are intentionally not editable here.
          // They are live runtime/session settings controlled exclusively
          // via the in-chat Group Settings dialog ("Realism & Needs" tab).
          // We preserve existing values on the GroupChat definition (see save logic).
        ],
      ),
    );
  }
}

/// Whether Save keeps the stored (unreadable) lorebook text: true keeps it,
/// false writes the entries on screen, null cancels the save. A readable
/// book is always written from the screen; an unreadable one is replaced
/// only when the user, asked here, says so.
Future<bool?> keepUnreadableGroupLorebook(
  BuildContext context, {
  required bool bookUnreadable,
  required bool hasEntries,
}) async {
  if (!bookUnreadable) return false;
  if (!hasEntries) return true;
  final replace = await showWarmDialog<bool>(
    context,
    title: 'Replace the old lorebook?',
    icon: Icons.menu_book,
    content: const WarmDialogText(
      "This group's old lorebook couldn't be read. Saving the entries you "
      'added replaces it for good. Keep it to save your other changes and '
      'leave the old lorebook as it is.',
    ),
    actions: [
      warmDialogCancel(context, label: 'Keep old lorebook', value: false),
      warmDialogConfirm(
        context,
        label: 'Replace it',
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ],
  );
  if (replace == null) return null;
  return !replace;
}
