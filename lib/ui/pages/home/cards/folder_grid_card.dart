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
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/character_card_grid.dart'
    show FolderDialogAction;
import 'package:front_porch_ai/ui/widgets/group_avatar_montage.dart';

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
  final void Function(CharacterCard character, CharacterFolder folder)
  onAcceptFolderDrop;
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

    return DragTarget<CharacterCard>(
      onAcceptWithDetails: (details) {
        onAcceptFolderDrop(details.data, folder);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
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
          child: InkWell(
            onTap: () => onFolderTap(folder),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isSmall = constraints.maxHeight < 200;
                final isTiny = constraints.maxHeight < 140;
                final iconSize = isTiny ? 32.0 : (isSmall ? 48.0 : 72.0);
                // Scale the preview to the card width so it fills a real chunk
                // of the card (and scales with the grid size) rather than a
                // fixed thumbnail that looks tiny on larger cards.
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
                      GroupAvatarMontage(images: previews, side: previewSide),
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
                      Text(
                        '$charCount character${charCount == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: isSmall ? 11 : 13,
                        ),
                      ),
                    ],
                    if (!isSmall) ...[
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.edit,
                              color: AppColors.iconSecondary(context),
                              size: 18,
                            ),
                            tooltip: 'Rename',
                            onPressed: () => onFolderDialogAction(
                              FolderDialogAction.rename,
                              folder: folder,
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.delete,
                              color: AppColors.negativeAccentOf(context),
                              size: 18,
                            ),
                            tooltip: 'Delete folder',
                            onPressed: () => onFolderDialogAction(
                              FolderDialogAction.delete,
                              folder: folder,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
