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
import 'package:front_porch_ai/ui/pages/worlds/world_library_rows.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/world_chain.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

import 'create_group_chat_page.dart';

const _loreEnabledAccent =
    Colors.blueAccent; // theme-keep: lorebook enabled vs always-on marker

class GroupLoreStep extends StatelessWidget {
  const GroupLoreStep({super.key, required this.draft, required this.actions});

  final GroupWizardDraft draft;
  final GroupWizardActions actions;

  @override
  Widget build(BuildContext context) {
    final worldRepo = Provider.of<WorldRepository>(context);
    final allWorlds = libraryDisplayOrder(worldRepo.placeWorlds);
    final byId = {for (final w in allWorlds) w.id: w};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Group Lorebook',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => _showLoreEntryEditor(context),
              icon: const Icon(Icons.add),
              label: const Text('Add Entry'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (draft.groupLoreEntries.isEmpty)
          const Text(
            'No group lore entries yet. These take highest priority in prompts.',
          )
        else
          ...draft.groupLoreEntries.asMap().entries.map((e) {
            final i = e.key;
            final entry = e.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.cardOf(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  width: 1.5,
                  color: entry.constant
                      ? AccentColors.amberOf(context).withValues(alpha: 0.3)
                      : entry.enabled
                      ? _loreEnabledAccent.withValues(alpha: 0.15)
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
                            ? AccentColors.amberOf(context)
                            : entry.enabled
                            ? _loreEnabledAccent
                            : AppColors.iconSecondary(context),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          entry.displayName,
                          style: TextStyle(
                            color: entry.enabled
                                ? AppColors.textPrimary(context)
                                : AppColors.textSecondary(context),
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
                            color: AccentColors.amberOf(
                              context,
                            ).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Always Active',
                            style: TextStyle(
                              color: AccentColors.amberOf(context),
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
                            color: _loreEnabledAccent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Depth ${entry.stickyDepth}',
                            style: const TextStyle(
                              color: _loreEnabledAccent,
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
                            draft.update(() {
                              entry.enabled = val;
                            });
                          },
                          activeTrackColor: AppColors.porchAmberOf(context),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.edit_outlined,
                          size: 16,
                          color: AppColors.textTertiary(context),
                        ),
                        onPressed: () => _showLoreEntryEditor(
                          context,
                          existing: entry,
                          index: i,
                        ),
                        tooltip: 'Edit entry',
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          size: 16,
                          color: StatusColors.dangerOf(context),
                        ),
                        onPressed: () => draft.deleteLoreEntry(i),
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
                                color: InkColors.washOf(context, 0.05, 0.04),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                k.trim(),
                                style: TextStyle(
                                  color: InkColors.mutedTextOf(context, 0.54),
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
          }),
        const SizedBox(height: 24),
        SwitchListTile(
          title: const Text('Inherit character & world lorebooks'),
          subtitle: const Text(
            'When on, member cards and their attached worlds contribute lore in addition to the group lorebook above.',
          ),
          value: draft.inheritCharacterLorebooks,
          onChanged: (v) =>
              draft.update(() => draft.inheritCharacterLorebooks = v),
        ),
        const SizedBox(height: 16),
        Text(
          'Linked Worlds',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ...draft.worldIds.map((wid) {
              final w = allWorlds.firstWhere(
                (ww) => ww.id == wid || ww.name == wid,
                orElse: () => World(
                  name: wid,
                  lorebook: Lorebook(entries: const []),
                ),
              );
              return Chip(
                label: Text(w.name),
                onDeleted: () =>
                    draft.toggleWorld(w.id.isNotEmpty ? w.id : wid),
              );
            }),
            OutlinedButton.icon(
              onPressed: () async {
                final chosen = await showDialog<World>(
                  context: context,
                  builder: (ctx) => SimpleDialog(
                    title: const Text('Link a World'),
                    children: linkableWorldsOf(allWorlds, (id) => byId[id])
                        .map(
                          (w) => SimpleDialogOption(
                            onPressed: () => Navigator.pop(ctx, w),
                            child: Text(w.name),
                          ),
                        )
                        .toList(),
                  ),
                );
                if (chosen != null) draft.toggleWorld(chosen.id);
              },
              icon: const Icon(Icons.public),
              label: const Text('Link World'),
            ),
          ],
        ),

        GroupWizardNavButtons(draft: draft, actions: actions, currentStep: 3),
      ],
    );
  }

  Future<void> _showLoreEntryEditor(
    BuildContext context, {
    LorebookEntry? existing,
    int? index,
  }) async {
    final result = await showLorebookEntryDialog(
      context: context,
      existing: existing,
      showEnabled: true,
    );
    if (result != null) {
      draft.putLoreEntry(result, index);
    }
  }
}
