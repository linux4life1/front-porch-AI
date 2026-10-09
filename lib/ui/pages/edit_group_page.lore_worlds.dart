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

part of 'edit_group_page.dart';

/// Lore & Worlds tab: the group lorebook (add/edit/delete entries), the
/// "inherit character & world lorebooks" toggle, and Linked Places (worlds)
/// chip picker. Split out of `edit_group_page.dart` (extension on
/// _EditGroupPageState) to keep every file under the 500-LOC cap — same
/// pattern model_settings_dialog.dart uses. Verbatim except `setState` ->
/// `rebuildState` (extensions can't call a State's protected members
/// directly). The `Provider.of<WorldRepository>(context)` call at the top
/// stays a LISTENING read (no `listen: false`) exactly as before — hoisting
/// it to the shell's build() would widen the rebuild scope to the whole page.
/// Shown on the Lore & Worlds tab when the stored group lorebook can't be read.
const kEditGroupUnreadableLoreNote =
    "This group's lorebook couldn't be read, so its entries aren't being "
    'used. New entries you add here can replace it; Save asks first.';

extension _EditGroupLoreWorldsTab on _EditGroupPageState {
  Widget _buildLoreWorldsTab() {
    final worldRepo = Provider.of<WorldRepository>(context);
    final allWorlds = worldRepo.placeWorlds;

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
                  final nameCtrl = TextEditingController();
                  final keyCtrl = TextEditingController();
                  final contentCtrl = TextEditingController();
                  bool enabled = true;
                  bool constant = false;

                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: AppColors.surfaceOf(context),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      title: const Text('Add Group Lore Entry'),
                      content: StatefulBuilder(
                        builder: (inner, setInner) => SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppTextField(
                                controller: nameCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Name',
                                ),
                              ),
                              const SizedBox(height: 8),
                              AppTextField(
                                controller: keyCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Key / Trigger',
                                ),
                              ),
                              const SizedBox(height: 8),
                              AppTextField(
                                controller: contentCtrl,
                                maxLines: 4,
                                decoration: const InputDecoration(
                                  labelText: 'Content',
                                ),
                              ),
                              const SizedBox(height: 12),
                              SwitchListTile(
                                title: const Text('Enabled'),
                                value: enabled,
                                onChanged: (v) => setInner(() => enabled = v),
                                dense: true,
                              ),
                              SwitchListTile(
                                title: const Text('Constant'),
                                value: constant,
                                onChanged: (v) => setInner(() => constant = v),
                                dense: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textSecondary(context),
                          ),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Add'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true && mounted) {
                    rebuildState(() {
                      _groupLoreEntries.add(
                        LorebookEntry(
                          name: nameCtrl.text.trim(),
                          key: keyCtrl.text.trim(),
                          content: contentCtrl.text.trim(),
                          enabled: enabled,
                          constant: constant,
                        ),
                      );
                    });
                  }
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Entry'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_bookUnreadable)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                kEditGroupUnreadableLoreNote,
                style: TextStyle(color: AppColors.porchAmberOf(context)),
              ),
            ),
          if (_groupLoreEntries.isEmpty)
            Text(
              'No group lore entries yet. These take highest priority in prompts.',
              style: TextStyle(color: AppColors.textSecondary(context)),
            )
          else
            ..._groupLoreEntries.asMap().entries.map((e) {
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
                      onPressed: () async {
                        final nameCtrl = TextEditingController(
                          text: entry.name,
                        );
                        final keyCtrl = TextEditingController(text: entry.key);
                        final contentCtrl = TextEditingController(
                          text: entry.content,
                        );
                        bool enabled = entry.enabled;
                        bool constant = entry.constant;

                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: AppColors.surfaceOf(context),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            title: const Text('Edit Group Lore Entry'),
                            content: StatefulBuilder(
                              builder: (inner, setInner) =>
                                  SingleChildScrollView(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        AppTextField(
                                          controller: nameCtrl,
                                          decoration: const InputDecoration(
                                            labelText: 'Name',
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        AppTextField(
                                          controller: keyCtrl,
                                          decoration: const InputDecoration(
                                            labelText: 'Key / Trigger',
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        AppTextField(
                                          controller: contentCtrl,
                                          maxLines: 4,
                                          decoration: const InputDecoration(
                                            labelText: 'Content',
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        SwitchListTile(
                                          title: const Text('Enabled'),
                                          value: enabled,
                                          onChanged: (v) =>
                                              setInner(() => enabled = v),
                                          dense: true,
                                        ),
                                        SwitchListTile(
                                          title: const Text('Constant'),
                                          value: constant,
                                          onChanged: (v) =>
                                              setInner(() => constant = v),
                                          dense: true,
                                        ),
                                      ],
                                    ),
                                  ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Save'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true && mounted) {
                          rebuildState(() {
                            _groupLoreEntries[i] = LorebookEntry(
                              name: nameCtrl.text.trim(),
                              key: keyCtrl.text.trim(),
                              content: contentCtrl.text.trim(),
                              enabled: enabled,
                              constant: constant,
                            );
                          });
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, size: 20),
                      onPressed: () =>
                          rebuildState(() => _groupLoreEntries.removeAt(i)),
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
            value: _inheritCharacterLorebooks,
            onChanged: (v) =>
                rebuildState(() => _inheritCharacterLorebooks = v),
          ),

          const SizedBox(height: 20),
          Text(
            'Linked Places',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Template for new chats of this group (climate + place lore).',
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
              ..._worldIds.map((wid) {
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
                  onDeleted: () => rebuildState(() => _worldIds.remove(wid)),
                );
              }),
              OutlinedButton.icon(
                onPressed: () async {
                  final chosen = await showDialog<World>(
                    context: context,
                    builder: (ctx) => SimpleDialog(
                      backgroundColor: AppColors.surfaceOf(context),
                      title: const Text('Link a Place'),
                      children: allWorlds
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
                      !_worldIds.contains(chosen.id) &&
                      !_worldIds.contains(chosen.name)) {
                    rebuildState(() => _worldIds.add(chosen.id));
                  }
                },
                icon: const Icon(Icons.public, size: 18),
                label: const Text('Link Place'),
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

  /// Whether Save keeps the stored (unreadable) lorebook text: true keeps it,
  /// false writes the entries on screen, null cancels the save. A readable
  /// book is always written from the screen; an unreadable one is replaced
  /// only when the user, asked here, says so.
  Future<bool?> _keepUnreadableLorebook() async {
    if (!_bookUnreadable) return false;
    if (_groupLoreEntries.isEmpty) return true;
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
}
