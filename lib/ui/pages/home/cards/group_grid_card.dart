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
import 'package:front_porch_ai/ui/pages/home/cards/home_card_menu.dart';
import 'package:front_porch_ai/ui/pages/home/cards/library_drag_ghost.dart';
import 'package:front_porch_ai/ui/pages/home/cards/library_drag_payload.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// A single group-chat card in the home grid — avatar montage, name, member
/// count, turn-order badge, and a right-click context menu. Extracted verbatim
/// from CharacterCardGrid._buildGroupCard (behavior-preserving).
///
/// Stateful ONLY to hold the member-avatar future: constructing it inline in
/// build issued a fresh SQLite query per tile on EVERY grid rebuild and
/// scroll recycle (and flashed an empty montage while each one resolved).
/// The future is created once per group and refreshed when the group object
/// changes (repository reloads produce new instances after any edit).
class GroupGridCard extends StatefulWidget {
  const GroupGridCard({
    super.key,
    required this.group,
    required this.groupRepo,
    required this.activeFolderId,
    required this.isSelecting,
    required this.isOrganizing,
    required this.selectedGroupIds,
    required this.onTapGroup,
    required this.onToggleSelectGroup,
    this.onGroupContextMenuAction,
    this.dragSelection,
    this.dimmed = false,
    this.onDragStarted,
    this.onDragEnded,
  });

  final GroupChat group;
  final GroupChatRepository groupRepo;
  final String? activeFolderId;
  final bool isSelecting;
  final bool isOrganizing;
  final Set<String> selectedGroupIds;
  final Future<void> Function(GroupChat group) onTapGroup;
  final void Function(GroupChat group) onToggleSelectGroup;

  /// Called when the user right-clicks (secondary tap) a group card.
  final void Function(String action, GroupChat group)? onGroupContextMenuAction;

  /// Set while this group is picked: holding it then drags every pick, with
  /// the stacked ghost. Null keeps the one-card drag.
  final LibraryDragPayload? dragSelection;

  /// Drawn at 40% while the picks it belongs to are being dragged.
  final bool dimmed;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnded;

  @override
  State<GroupGridCard> createState() => _GroupGridCardState();
}

class _GroupGridCardState extends State<GroupGridCard> {
  late Future<List<File>> _avatarsFuture;

  @override
  void initState() {
    super.initState();
    _avatarsFuture = widget.groupRepo.getMemberAvatarFiles(widget.group.id);
  }

  @override
  void didUpdateWidget(GroupGridCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Repository reloads hand out new GroupChat instances after any edit, so
    // an identity change is the "membership may have changed" signal.
    if (!identical(widget.group, oldWidget.group)) {
      _avatarsFuture = widget.groupRepo.getMemberAvatarFiles(widget.group.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final isSelecting = widget.isSelecting;
    final isOrganizing = widget.isOrganizing;
    final onTapGroup = widget.onTapGroup;
    // Local shadow so Dart can promote the null-check across the closure below
    // (a field can't be promoted, but a local can).
    final onGroupContextMenuAction = widget.onGroupContextMenuAction;
    final isSelectedCard = widget.selectedGroupIds.contains(group.id);
    return FutureBuilder<List<File>>(
      future: _avatarsFuture,
      builder: (context, snapshot) {
        final memberFiles = snapshot.data ?? <File>[];
        final card = Card(
          color: AppColors.cardOf(context),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isSelectedCard
                  ? AppColors.porchTerracottaOf(context)
                  : AppColors.porchTerracottaOf(context).withValues(alpha: 0.3),
              width: isSelectedCard ? 2.5 : 1,
            ),
          ),
          child: InkWell(
            onTap: () async {
              if (isSelecting || isOrganizing) {
                widget.onToggleSelectGroup(group);
                return;
              }
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

                // Selection check circle — parity with character cards.
                if (isSelecting || isOrganizing)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: isSelectedCard
                            ? (isOrganizing
                                  ? AppColors.porchHoneyOf(context)
                                  : AppColors.porchTerracottaOf(context))
                            : AppColors.resolve(
                                context,
                                Colors.black54,
                                Colors.black12,
                              ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelectedCard
                              ? (isOrganizing
                                    ? AppColors.porchHoneyOf(context)
                                    : AppColors.porchTerracottaOf(context))
                              : AppColors.resolve(
                                  context,
                                  Colors.white38,
                                  Colors.black38,
                                ),
                          width: 2,
                        ),
                      ),
                      child: isSelectedCard
                          ? const Icon(
                              Icons.check,
                              size: 16,
                              color: Colors.white,
                            )
                          : null,
                    ),
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
                          items: groupCardMenuItems(
                            context,
                            inFolder: widget.activeFolderId != null,
                          ),
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

        // Group casts drag into folders exactly like characters do — the
        // folder drop targets accept either kind (they were CharacterCard-only,
        // which is why groups couldn't be dragged at all).
        final picks = widget.dragSelection;
        final montage = memberFiles.isEmpty
            ? Icon(
                Icons.groups,
                size: 64,
                color: AppColors.porchTerracottaOf(context),
              )
            : Center(
                child: GroupAvatarMontage(
                  images: memberFiles.take(4).toList(),
                  side: 120,
                ),
              );
        // Always an Opacity, so dimming mid-drag never rebuilds the draggable.
        return Opacity(
          opacity: widget.dimmed ? 0.4 : 1,
          child: LongPressDraggable<Object>(
            data: picks ?? group,
            delay: kFolderDragHoldDelay,
            dragAnchorStrategy: picks == null
                ? childDragAnchorStrategy
                : LibraryDragGhost.anchor,
            onDragStarted: widget.onDragStarted,
            onDragEnd: (_) => widget.onDragEnded?.call(),
            feedback: picks != null
                ? LibraryDragGhost(
                    count: picks.count,
                    name: group.name,
                    cover: ColoredBox(
                      color: AppColors.porchTerracottaOf(
                        context,
                      ).withValues(alpha: 0.12),
                      child: FittedBox(child: montage),
                    ),
                  )
                : Material(
                    color: Colors.transparent,
                    child: SizedBox(
                      width: 150,
                      height: 200,
                      child: Card(
                        color: AppColors.cardOf(context),
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ColoredBox(
                          color: AppColors.porchTerracottaOf(
                            context,
                          ).withValues(alpha: 0.12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: montage,
                          ),
                        ),
                      ),
                    ),
                  ),
            childWhenDragging: picks == null
                ? Opacity(opacity: 0.3, child: card)
                : card,
            child: card,
          ),
        );
      },
    );
  }
}
