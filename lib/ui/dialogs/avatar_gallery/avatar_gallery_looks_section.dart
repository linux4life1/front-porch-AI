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

import 'package:front_porch_ai/services/avatar_gallery.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_controller.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_section_header.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_tile.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The "Gallery avatars" section — the portrait + hand-picked alternates
/// (outfits, scenes, moods). In-chat, tapping a tile shows it in this chat; the
/// ★ marks the one canonical avatar; ✕ deletes. Pure presentation over the
/// [AvatarGalleryController]; the add + replace-portrait flows (pickers) are the
/// shell's callbacks.
class AvatarGalleryLooksSection extends StatelessWidget {
  const AvatarGalleryLooksSection({
    super.key,
    required this.controller,
    required this.onAddLook,
    required this.onReplacePortrait,
    required this.onDelete,
    required this.onDeletePortrait,
  });

  final AvatarGalleryController controller;
  final VoidCallback onAddLook;
  final VoidCallback onReplacePortrait;

  /// Confirm + delete a gallery avatar (the shell owns the confirm dialog).
  final ValueChanged<String> onDelete;

  /// Confirm + delete the portrait (a look gets promoted in its place).
  /// Only offered when at least one gallery look exists.
  final VoidCallback onDeletePortrait;

  bool get _inChat => controller.mode == WardrobeMode.inChat;

  @override
  Widget build(BuildContext context) {
    final portrait = controller.portraitFile();
    final selected = controller.selectedFaceId;
    final tiles = <Widget>[];

    // Portrait tile (always, when a portrait exists).
    if (portrait != null) {
      tiles.add(
        AvatarTile(
          imageFile: portrait,
          caption: 'Portrait',
          starred: controller.favoriteId == null,
          onStar: () => controller.setFavorite(null),
          actionLabel: 'Replace portrait',
          onAction: onReplacePortrait,
          // Deletable only when a look exists to take its place.
          onDelete: controller.looks.isEmpty ? null : onDeletePortrait,
          onTap: _inChat
              ? () => controller.selectFaceInChat(kPortraitFaceId)
              : null,
          badge: _inChat && (selected == null || selected == kPortraitFaceId)
              ? 'Showing'
              : null,
          highlighted:
              _inChat && (selected == null || selected == kPortraitFaceId),
          badgeColor: AppColors.formMasterAccent,
        ),
      );
    }

    // Gallery avatars.
    for (final look in controller.looks) {
      tiles.add(
        AvatarTile(
          imageFile: controller.fileFor(look),
          starred: controller.favoriteId == look.id,
          onStar: () => controller.setFavorite(look.id),
          onDelete: () => onDelete(look.id),
          onTap: _inChat ? () => controller.selectFaceInChat(look.id) : null,
          badge: _inChat && selected == look.id ? 'Showing' : null,
          highlighted: _inChat && selected == look.id,
          badgeColor: AppColors.formMasterAccent,
        ),
      );
    }

    // Add tile.
    tiles.add(GalleryAddTile(label: 'Add avatar', onTap: onAddLook));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AvatarGallerySectionHeader(
          title: 'Gallery avatars',
          subtitle: _inChat
              ? 'Tap one to show it in this chat · ★ sets the default'
              : 'Outfits, scenes, moods · ★ sets the default + card cover',
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.8,
          children: tiles,
        ),
      ],
    );
  }
}
