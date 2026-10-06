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
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/home/cards/home_card_menu.dart';
import 'package:front_porch_ai/ui/pages/home/cards/library_drag_payload.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// A single folder card in the home grid — a 2x2 preview montage (or a folder
/// icon when empty), name, character count, and rename/delete actions. It is a
/// drop target for moving characters into the folder. Extracted verbatim from
/// CharacterCardGrid._buildFolderCard (behavior-preserving).
class FolderGridCard extends StatelessWidget {
  const FolderGridCard({
    super.key,
    required this.folder,
    required this.onAcceptFolderDrop,
    required this.onFolderTap,
    required this.onFolderDialogAction,
    required this.onResolveCharImage,
  });

  final CharacterFolder folder;

  /// Fired when a card is dropped on this folder. [item] is the dragged
  /// [CharacterCard] **or** [GroupChat] — one callback for both kinds rather
  /// than parallel character/group drop paths.
  final void Function(Object item, CharacterFolder folder) onAcceptFolderDrop;
  final void Function(CharacterFolder folder) onFolderTap;
  final void Function(
    FolderDialogAction action, {
    CharacterFolder? folder,
    String? parentId,
  })
  onFolderDialogAction;
  final File Function(CharacterCard card) onResolveCharImage;

  List<File> _folderPreviewImages(
    BuildContext context,
    CharacterFolder folder,
    int max,
  ) {
    if (folder.characterPaths.isEmpty) return const [];
    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final byFilename = <String, CharacterCard>{};
    for (final c in repo.characters) {
      final p = c.imagePath;
      if (p != null) byFilename.putIfAbsent(path.basename(p), () => c);
    }
    final files = <File>[];
    for (final ref in folder.characterPaths) {
      final card = byFilename[path.basename(ref)];
      if (card != null) {
        files.add(onResolveCharImage(card));
        if (files.length >= max) break;
      }
    }
    return files;
  }

  @override
  Widget build(BuildContext context) {
    final charCount = folder.characterPaths.length;
    final groupCount = folder.groupIds.length;

    // Object (not CharacterCard) so group casts and a dragged selection can
    // be dropped here too — typed as the base with an explicit will-accept
    // guard, so an unrelated draggable neither highlights the folder nor
    // fires the callback.
    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) => libraryDragCount(details.data) > 0,
      onAcceptWithDetails: (details) {
        onAcceptFolderDrop(details.data, folder);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        // While something hovers, the count line says what a drop does.
        final dropping = isHovering ? libraryDragCount(candidateData.first) : 0;
        return Card(
          color: isHovering
              ? AppColors.porchAmberOf(context).withValues(alpha: 0.15)
              : AppColors.cardOf(context),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isHovering
                  ? AppColors.porchAmberOf(context)
                  : AppColors.borderOf(context),
              width: isHovering ? 2 : 1,
            ),
          ),
          child: Stack(
            children: [
              // Positioned.fill, NOT a bare child. A non-positioned Stack child
              // gets LOOSE constraints and top-left alignment, so this InkWell
              // shrink-wrapped to the width of its widest line ("N characters")
              // and sat against the left edge. Two visible bugs from one cause:
              // the card's content looked left-aligned instead of centred, and
              // only that narrow strip was clickable — while right-click worked
              // everywhere, because THAT handler below already uses
              // Positioned.fill. Filling also gives LayoutBuilder the card's
              // real width, which `previewSide = maxWidth * 0.78` depends on.
              Positioned.fill(
                child: InkWell(
                  onTap: () => onFolderTap(folder),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isSmall = constraints.maxHeight < 200;
                      final isTiny = constraints.maxHeight < 140;
                      final iconSize = isTiny ? 32.0 : (isSmall ? 48.0 : 72.0);
                      // Scale the preview to the card width so it fills a real
                      // chunk of the card (and scales with the grid size) rather
                      // than a fixed thumbnail that looks tiny on larger cards.
                      final previewSide = (constraints.maxWidth * 0.78).clamp(
                        64.0,
                        220.0,
                      );
                      final fontSize = isTiny ? 11.0 : (isSmall ? 13.0 : 16.0);

                      // Preview the first few characters inside the folder (2x2).
                      // Empty folders fall back to the plain folder icon.
                      final previews = _folderPreviewImages(context, folder, 4);

                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (previews.isEmpty)
                            Icon(
                              Icons.folder,
                              size: iconSize,
                              color: isHovering
                                  ? AppColors.porchAmberOf(context)
                                  : AppColors.iconSecondary(context),
                            )
                          else
                            GroupAvatarMontage(
                              images: previews,
                              side: previewSide,
                            ),
                          SizedBox(height: isTiny ? 4 : (isSmall ? 8 : 16)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              folder.name,
                              style: TextStyle(
                                color: AppColors.textPrimary(context),
                                fontWeight: FontWeight.bold,
                                fontSize: fontSize,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: isTiny ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!isTiny) ...[
                            SizedBox(height: isSmall ? 4 : 8),
                            // Same horizontal padding + ellipsis as the name
                            // above. Without them this line rendered edge to
                            // edge and got clipped by the card's rounded
                            // corner on a narrow grid — the count is the
                            // widest thing on an empty folder card.
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: dropping > 0
                                  ? Text(
                                      'Drop to move $dropping here',
                                      style: TextStyle(
                                        color: AppColors.porchAmberOf(context),
                                        fontSize: isSmall ? 11 : 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    )
                                  : Text(
                                      groupCount > 0
                                          ? '$charCount character${charCount == 1 ? '' : 's'}'
                                                ' · $groupCount group${groupCount == 1 ? '' : 's'}'
                                          : '$charCount character${charCount == 1 ? '' : 's'}',
                                      style: TextStyle(
                                        color: AppColors.textSecondary(context),
                                        fontSize: isSmall ? 11 : 13,
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                            ),
                          ],
                          // The old inline Rename/Delete icon row lived behind
                          // `if (!isSmall)`, so at any grid size under 200 px
                          // tall it was not rendered AT ALL — which is why folder
                          // deletion read as "there is no way to delete a
                          // folder". The actions now live in the always-present
                          // ⋮ menu (and on right-click), so they exist at every
                          // grid size.
                        ],
                      );
                    },
                  ),
                ),
              ),
              // Always-visible menu affordance + right-click, matching the
              // character/group cards (and the web library's kebab).
              Positioned(
                top: 4,
                right: 4,
                child: _FolderMenuButton(
                  folder: folder,
                  onFolderDialogAction: onFolderDialogAction,
                ),
              ),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onSecondaryTapUp: (details) => _showFolderMenu(
                    context,
                    details.globalPosition,
                    folder,
                    onFolderDialogAction,
                  ),
                  child: const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Rename / new subfolder / delete for a folder card. Shared by the corner ⋮
/// button and the right-click handler so the two can never offer different
/// actions.
void _showFolderMenu(
  BuildContext context,
  Offset position,
  CharacterFolder folder,
  void Function(
    FolderDialogAction action, {
    CharacterFolder? folder,
    String? parentId,
  })
  onFolderDialogAction,
) {
  showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx,
      position.dy,
    ),
    color: AppColors.surfaceContainerOf(context),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    items: [
      homeCardMenuItem(
        context,
        value: 'rename',
        icon: Icons.drive_file_rename_outline,
        label: 'Rename Folder',
      ),
      homeCardMenuItem(
        context,
        value: 'subfolder',
        icon: Icons.create_new_folder,
        label: 'New Subfolder',
        iconColor: AppColors.porchAmberOf(context),
      ),
      homeCardMenuItem(
        context,
        value: 'delete',
        icon: Icons.delete,
        label: 'Delete Folder…',
        iconColor: AppColors.negativeAccentOf(context),
        labelColor: AppColors.negativeAccentOf(context),
      ),
    ],
  ).then((value) {
    switch (value) {
      case 'rename':
        onFolderDialogAction(FolderDialogAction.rename, folder: folder);
        break;
      case 'subfolder':
        onFolderDialogAction(FolderDialogAction.create, parentId: folder.id);
        break;
      case 'delete':
        onFolderDialogAction(FolderDialogAction.delete, folder: folder);
        break;
    }
  });
}

/// The corner ⋮ button. Stateful only to resolve its own screen position for
/// the popup anchor.
class _FolderMenuButton extends StatelessWidget {
  const _FolderMenuButton({
    required this.folder,
    required this.onFolderDialogAction,
  });

  final CharacterFolder folder;
  final void Function(
    FolderDialogAction action, {
    CharacterFolder? folder,
    String? parentId,
  })
  onFolderDialogAction;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.more_vert,
        size: 18,
        color: AppColors.iconSecondary(context),
      ),
      tooltip: 'Folder actions (rename, delete)',
      visualDensity: VisualDensity.compact,
      onPressed: () {
        final box = context.findRenderObject() as RenderBox?;
        final pos =
            box?.localToGlobal(box.size.bottomLeft(Offset.zero)) ?? Offset.zero;
        _showFolderMenu(context, pos, folder, onFolderDialogAction);
      },
    );
  }
}
