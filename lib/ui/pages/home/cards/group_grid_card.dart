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

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/group_avatar_montage.dart';

/// A single group-chat card in the home grid — avatar montage, name, member
/// count, turn-order badge, and a right-click context menu. Extracted verbatim
/// from CharacterCardGrid._buildGroupCard (behavior-preserving).
class GroupGridCard extends StatelessWidget {
  const GroupGridCard({
    super.key,
    required this.group,
    required this.groupRepo,
    required this.isSelecting,
    required this.isOrganizing,
    required this.onTapGroup,
    this.onGroupContextMenuAction,
  });

  final GroupChat group;
  final GroupChatRepository groupRepo;
  final bool isSelecting;
  final bool isOrganizing;
  final Future<void> Function(GroupChat group) onTapGroup;

  /// Called when the user right-clicks (secondary tap) a group card.
  final void Function(String action, GroupChat group)? onGroupContextMenuAction;

  @override
  Widget build(BuildContext context) {
    // Local shadow so Dart can promote the null-check across the closure below
    // (a field can't be promoted, but a local can).
    final onGroupContextMenuAction = this.onGroupContextMenuAction;
    return FutureBuilder<List<File>>(
      future: groupRepo.getMemberAvatarFiles(group.id),
      builder: (context, snapshot) {
        final memberFiles = snapshot.data ?? <File>[];
        return Card(
          color: AppColors.cardOf(context),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: AppColors.porchTerracottaOf(context).withValues(alpha: 0.3),
            ),
          ),
          child: InkWell(
            onTap: () async {
              await onTapGroup(group);
            },
            child: Stack(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final h = constraints.maxHeight;
                    final isCompactGroup = h < 220;
                    final nameFontSize = isCompactGroup ? 12.0 : 16.0;
                    final subFontSize = isCompactGroup ? 10.0 : 13.0;
                    final badgeFontSize = isCompactGroup ? 9.0 : 11.0;
                    // Folder-style avatar montage: bigger than the old overlapping
                    // circles, filling the top of the card.
                    final gridSide = (constraints.maxWidth * 0.78).clamp(
                      110.0,
                      230.0,
                    );

                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(height: isCompactGroup ? 8 : 16),
                        SizedBox(
                          width: double.infinity,
                          child: Center(
                            child: GroupAvatarMontage(
                              images: memberFiles.take(4).toList(),
                              side: gridSide,
                            ),
                          ),
                        ),
                        SizedBox(height: isCompactGroup ? 8 : 12),
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              group.name,
                              style: TextStyle(
                                color: AppColors.textPrimary(context),
                                fontWeight: FontWeight.bold,
                                fontSize: nameFontSize,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: isCompactGroup ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        if (!isCompactGroup) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${memberFiles.length} character${memberFiles.length == 1 ? '' : 's'}',
                            style: TextStyle(
                              color: AppColors.textSecondary(context),
                              fontSize: subFontSize,
                            ),
                          ),
                        ],
                        SizedBox(height: isCompactGroup ? 2 : 4),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isCompactGroup ? 4 : 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.porchTerracottaOf(
                              context,
                            ).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            group.turnOrder == TurnOrder.roundRobin
                                ? 'Round Robin'
                                : 'Random',
                            style: TextStyle(
                              color: AppColors.porchTerracottaOf(context),
                              fontSize: badgeFontSize,
                            ),
                          ),
                        ),
                        SizedBox(height: isCompactGroup ? 4 : 0),
                      ],
                    );
                  },
                ),

                // Right-click (secondary tap) context menu for groups — parity with character cards.
                // Only active when not in bulk select/organize modes (same guard as characters).
                if (!isSelecting &&
                    !isOrganizing &&
                    onGroupContextMenuAction != null)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onSecondaryTapUp: (details) {
                        final position = details.globalPosition;
                        showMenu<String>(
                          context: context,
                          position: RelativeRect.fromLTRB(
                            position.dx,
                            position.dy,
                            position.dx,
                            position.dy,
                          ),
                          color: AppColors.surfaceContainerOf(context),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          items: [
                            PopupMenuItem(
                              value: 'edit',
                              child: ListTile(
                                leading: Icon(
                                  Icons.edit,
                                  color: AppColors.iconSecondary(context),
                                  size: 20,
                                ),
                                title: Text(
                                  'Edit Group',
                                  style: TextStyle(
                                    color: AppColors.textPrimary(context),
                                  ),
                                ),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            PopupMenuItem(
                              value: 'duplicate',
                              child: ListTile(
                                leading: Icon(
                                  Icons.copy,
                                  color: AppColors.iconSecondary(context),
                                  size: 20,
                                ),
                                title: Text(
                                  'Duplicate Group',
                                  style: TextStyle(
                                    color: AppColors.textPrimary(context),
                                  ),
                                ),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            PopupMenuItem(
                              value: 'export',
                              child: ListTile(
                                leading: Icon(
                                  Icons.upload,
                                  color: AppColors.iconSecondary(context),
                                  size: 20,
                                ),
                                title: Text(
                                  'Export PNG',
                                  style: TextStyle(
                                    color: AppColors.textPrimary(context),
                                  ),
                                ),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            PopupMenuItem(
                              value: 'extract',
                              child: ListTile(
                                leading: Icon(
                                  Icons.call_split,
                                  color: AppColors.journalAccentOf(context),
                                  size: 20,
                                ),
                                title: Text(
                                  'Extract Characters',
                                  style: TextStyle(
                                    color: AppColors.textPrimary(context),
                                  ),
                                ),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: ListTile(
                                leading: Icon(
                                  Icons.delete,
                                  color: AppColors.negativeAccentOf(context),
                                  size: 20,
                                ),
                                title: Text(
                                  'Delete',
                                  style: TextStyle(
                                    color: AppColors.negativeAccentOf(context),
                                  ),
                                ),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ],
                        ).then((value) {
                          if (value == null) return;
                          onGroupContextMenuAction(value, group);
                        });
                      },
                      child: const SizedBox.shrink(),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
