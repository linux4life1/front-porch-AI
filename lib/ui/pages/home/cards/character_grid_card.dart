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
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// A single character card in the home grid: draggable (for folder organizing),
/// selectable, with the avatar/name/message-count body and a right-click
/// context menu. Scene Guests (Lite NPCs) get a "Guest" badge. Extracted
/// verbatim from CharacterCardGrid — behavior-preserving.
class CharacterGridCard extends StatelessWidget {
  const CharacterGridCard({
    super.key,
    required this.character,
    required this.activeFolderId,
    required this.messageCountCache,
    required this.isSelecting,
    required this.isOrganizing,
    required this.selectedCharacterIds,
    required this.onTapCharacter,
    required this.onToggleSelect,
    required this.onContextMenuAction,
    required this.onResolveCharImage,
  });

  final CharacterCard character;
  final String? activeFolderId;
  final Map<String, int> messageCountCache;
  final bool isSelecting;
  final bool isOrganizing;
  final Set<String> selectedCharacterIds;
  final Future<void> Function(CharacterCard character) onTapCharacter;
  final void Function(CharacterCard character) onToggleSelect;
  final void Function(String action, CharacterCard character)
  onContextMenuAction;
  final File Function(CharacterCard card) onResolveCharImage;

  /// Delegates to the canonical stable group ID.
  String _getCharacterIdFromCard(CharacterCard card) => card.stableGroupId;

  @override
  Widget build(BuildContext context) {
    return LongPressDraggable<CharacterCard>(
      data: character,
      feedback: Material(
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
            child: character.imagePath != null
                ? Image.file(
                    onResolveCharImage(character),
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    errorBuilder: (_, _, _) => Container(
                      color: AppColors.surfaceContainerOf(context),
                      child: Icon(
                        Icons.person,
                        color: AppColors.iconSecondary(context),
                        size: 48,
                      ),
                    ),
                  )
                : Icon(
                    Icons.person,
                    size: 64,
                    color: AppColors.iconSecondary(context),
                  ),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildCharacterCardInner(context, character),
      ),
      // Scene Guests (Lite NPCs) are real library cards (so they persist and can
      // be deleted here), but badge them so they're distinguishable from regular
      // characters in the grid.
      child: character.isLite
          ? Stack(
              children: [
                _buildCharacterCardInner(context, character),
                Positioned(top: 6, left: 6, child: _guestBadge(context)),
              ],
            )
          : _buildCharacterCardInner(context, character),
    );
  }

  /// Small "Guest" chip overlaid on Scene Guest (Lite NPC) cards in the grid.
  Widget _guestBadge(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.relationshipAccent.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(6),
    ),
    child: const Text(
      'Guest',
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    ),
  );

  Widget _buildCharacterCardInner(
    BuildContext context,
    CharacterCard character,
  ) {
    final charId = _getCharacterIdFromCard(character);
    final msgCount = messageCountCache[charId] ?? 0;

    final stringId = _getCharacterIdFromCard(character);
    final isSelectedCard = selectedCharacterIds.contains(stringId);

    return Card(
      color: AppColors.cardOf(context),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelectedCard
              ? AppColors.porchTerracottaOf(context)
              : AppColors.borderOf(context).withValues(alpha: 0.3),
          width: isSelectedCard ? 2.5 : 1,
        ),
      ),
      child: Stack(
        children: [
          InkWell(
            onTap: () async {
              if (isSelecting || isOrganizing) {
                onToggleSelect(character);
                return;
              }
              await onTapCharacter(character);
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 200;
                final isTiny = constraints.maxWidth < 160;

                if (isTiny) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      character.imagePath != null
                          ? Image.file(
                              onResolveCharImage(character),
                              fit: BoxFit.cover,
                              alignment: Alignment.topCenter,
                              errorBuilder: (_, _, _) => Container(
                                color: AppColors.surfaceContainerOf(context),
                                child: Icon(
                                  Icons.person,
                                  size: 32,
                                  color: AppColors.iconSecondary(context),
                                ),
                              ),
                            )
                          : Container(
                              color: AppColors.surfaceContainerOf(context),
                              child: Icon(
                                Icons.person,
                                size: 32,
                                color: AppColors.iconSecondary(context),
                              ),
                            ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                AppColors.resolve(
                                  context,
                                  Colors.black87,
                                  Colors.black54,
                                ),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: Text(
                            character.name,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: isCompact ? 4 : 3,
                      child: character.imagePath != null
                          ? Image.file(
                              onResolveCharImage(character),
                              fit: BoxFit.cover,
                              alignment: Alignment.topCenter,
                              errorBuilder: (_, _, _) => Container(
                                color: AppColors.surfaceContainerOf(context),
                                child: Icon(
                                  Icons.person,
                                  size: isCompact ? 32 : 64,
                                  color: AppColors.iconSecondary(context),
                                ),
                              ),
                            )
                          : Container(
                              color: AppColors.surfaceContainerOf(context),
                              child: Icon(
                                Icons.person,
                                size: isCompact ? 32 : 64,
                                color: AppColors.iconSecondary(context),
                              ),
                            ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Padding(
                        padding: EdgeInsets.all(isCompact ? 6.0 : 12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    character.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          fontSize: isCompact ? 12 : null,
                                        ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (msgCount > 0)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.chat_bubble_outline,
                                        size: 11,
                                        color: AppColors.iconSecondary(context),
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        '$msgCount',
                                        style: TextStyle(
                                          color: AppColors.textTertiary(
                                            context,
                                          ),
                                          fontSize: isCompact ? 10 : 11,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                            if (!isCompact) ...[
                              const SizedBox(height: 4),
                              if (character.tags.isNotEmpty)
                                Flexible(
                                  child: Wrap(
                                    spacing: 4,
                                    runSpacing: 2,
                                    children: character.tags
                                        .take(3)
                                        .map(
                                          (tag) => Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.porchAmberOf(
                                                context,
                                              ).withValues(alpha: 0.18),
                                              border: Border.all(
                                                color: AppColors.porchAmberOf(
                                                  context,
                                                ).withValues(alpha: 0.4),
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              tag,
                                              style: TextStyle(
                                                color: AppColors.porchAmberOf(
                                                  context,
                                                ),
                                                fontSize: 10,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                )
                              else
                                Flexible(
                                  child: Text(
                                    character.formattedDescription,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
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
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
            ),
          if (!isSelecting && !isOrganizing)
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
                            'Edit Character',
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                            ),
                          ),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'avatar_gallery',
                        child: ListTile(
                          leading: Icon(
                            Icons.photo_library_outlined,
                            color: AppColors.iconSecondary(context),
                            size: 20,
                          ),
                          title: Text(
                            'Avatar Gallery',
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
                            'Duplicate Character',
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
                        value: 'export_json',
                        child: ListTile(
                          leading: Icon(
                            Icons.data_object,
                            color: AppColors.iconSecondary(context),
                            size: 20,
                          ),
                          title: Text(
                            'Export JSON',
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                            ),
                          ),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      if (activeFolderId != null)
                        PopupMenuItem(
                          value: 'remove_folder',
                          child: ListTile(
                            leading: Icon(
                              Icons.folder_off,
                              color: AppColors.porchAmberOf(context),
                              size: 20,
                            ),
                            title: Text(
                              'Remove from Folder',
                              style: TextStyle(
                                color: AppColors.porchAmberOf(context),
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
                    onContextMenuAction(value, character);
                  });
                },
                child: const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }

}
