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
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/worlds/world_library_rows.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// The character editor's Worlds tab. Linking a place edits
/// [selectedWorldNames] in place and then calls [onChanged].
class EditCharacterWorldsTab extends StatelessWidget {
  final List<String> selectedWorldNames;
  final VoidCallback onChanged;

  const EditCharacterWorldsTab({
    super.key,
    required this.selectedWorldNames,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<WorldRepository>(
      builder: (context, repo, child) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Linked Worlds',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Attach worlds so their lore and climate apply in this character\'s chats. '
                    'Chats start at the world\'s starred place. '
                    'To copy another character\'s lore into this card, use Lorebook → From character.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (repo.linkableWorlds.isEmpty)
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
                              Icons.public,
                              size: 48,
                              color: InkColors.washOf(context, 0.12, 0.12),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No places found',
                              style: TextStyle(
                                color: AppColors.textTertiary(context),
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Create places in the Worlds section.',
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
                    ...repo.linkableWorlds.map((world) {
                      final inside = linkPickerInsideLine(
                        world,
                        repo.placeWorlds,
                      );
                      final isLinked =
                          selectedWorldNames.contains(world.id) ||
                          selectedWorldNames.contains(world.name);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: AppColors.cardOf(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isLinked
                                ? AppColors.formAccentOf(
                                    context,
                                  ).withValues(alpha: 0.4)
                                : AppColors.borderOf(
                                    context,
                                  ).withValues(alpha: 0.45),
                          ),
                        ),
                        child: ListTile(
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isLinked
                                  ? AppColors.formAccentOf(
                                      context,
                                    ).withValues(alpha: 0.2)
                                  : InkColors.washOf(context, 0.05, 0.05),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.public,
                              size: 20,
                              color: isLinked
                                  ? AppColors.formAccentOf(context)
                                  : AppColors.textTertiary(context),
                            ),
                          ),
                          title: Text(
                            world.name,
                            style: TextStyle(
                              color: isLinked
                                  ? AppColors.textPrimary(context)
                                  : AppColors.textSecondary(context),
                              fontWeight: isLinked
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final line in [
                                world.description.isNotEmpty
                                    ? world.description
                                    : '${world.lorebook.entries.length} entries',
                                ?inside,
                              ])
                                Text(
                                  line,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.textTertiary(context),
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                          trailing: Switch(
                            value: isLinked,
                            onChanged: (val) {
                              if (val) {
                                selectedWorldNames.remove(world.name);
                                if (!selectedWorldNames.contains(world.id)) {
                                  selectedWorldNames.add(world.id);
                                }
                              } else {
                                selectedWorldNames.remove(world.id);
                                selectedWorldNames.remove(world.name);
                              }
                              onChanged();
                            },
                            activeTrackColor: AppColors.formAccentOf(
                              context,
                            ).withValues(alpha: 0.5),
                            activeThumbColor: AppColors.formAccentOf(context),
                          ),
                        ),
                      );
                    }),

                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
