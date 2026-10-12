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

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// One row of a home-grid card's right-click menu. Character and group cards
/// were each hand-rolling the identical 18-line PopupMenuItem/ListTile shape
/// per entry (≈14 copies between them), which is what pushed
/// character_grid_card past the size cap. Colours default to the standard
/// treatment; [iconColor]/[labelColor] cover the accented (amber) and
/// destructive (red) rows.
PopupMenuItem<String> homeCardMenuItem(
  BuildContext context, {
  required String value,
  required IconData icon,
  required String label,
  Color? iconColor,
  Color? labelColor,
}) {
  return PopupMenuItem<String>(
    value: value,
    child: ListTile(
      leading: Icon(
        icon,
        color: iconColor ?? AppColors.iconSecondary(context),
        size: 20,
      ),
      title: Text(
        label,
        style: TextStyle(color: labelColor ?? AppColors.textPrimary(context)),
      ),
      dense: true,
      contentPadding: EdgeInsets.zero,
    ),
  );
}

/// The character card's full right-click menu, extracted from
/// character_grid_card.dart (which had crossed the 500-line cap). Values are
/// dispatched by `_handleContextMenuAction` in home_page_chrome.dart.
List<PopupMenuItem<String>> characterCardMenuItems(
  BuildContext context, {
  required bool inFolder,
}) {
  return [
    // Start-fresh sits first: it's the most common intent after "open", and
    // it picks its own persona (never inheriting whatever the last chat used).
    homeCardMenuItem(
      context,
      value: 'new_chat',
      icon: Icons.add_comment_outlined,
      label: 'Start New Chat',
      iconColor: AppColors.porchAmberOf(context),
    ),
    homeCardMenuItem(
      context,
      value: 'chat_history',
      icon: Icons.history,
      label: 'Manage Chats',
    ),
    homeCardMenuItem(
      context,
      value: 'edit',
      icon: Icons.edit,
      label: 'Edit Character',
    ),
    // Grow the card from a real chat: interview + rewrite grounded in how the
    // character was actually played. Saves as a new "(Enhanced)" duplicate.
    homeCardMenuItem(
      context,
      value: 'ai_enhance',
      icon: Icons.auto_awesome,
      label: 'AI Enhance',
      iconColor: AppColors.porchAmberOf(context),
    ),
    homeCardMenuItem(
      context,
      value: 'avatar_gallery',
      icon: Icons.photo_library_outlined,
      label: 'Avatar Gallery',
    ),
    homeCardMenuItem(
      context,
      value: 'duplicate',
      icon: Icons.copy,
      label: 'Duplicate Character',
    ),
    // SillyTavern's "Convert to Persona": a copy you can play as.
    homeCardMenuItem(
      context,
      value: 'use_as_persona',
      icon: Icons.switch_account,
      label: 'Use as Persona',
    ),
    homeCardMenuItem(
      context,
      value: 'export',
      icon: Icons.upload,
      label: 'Export PNG',
    ),
    homeCardMenuItem(
      context,
      value: 'export_json',
      icon: Icons.data_object,
      label: 'Export JSON',
    ),
    // Filing a single character was drag-only before this — the menu could
    // take one OUT of a folder but never put one in, or move it between
    // folders (the picker lists every folder by full path, so it doubles as
    // "move up one level" when nested). Group cards already had this.
    homeCardMenuItem(
      context,
      value: 'move_folder',
      icon: Icons.drive_file_move,
      label: 'Move to Folder…',
      iconColor: AppColors.porchAmberOf(context),
    ),
    if (inFolder)
      homeCardMenuItem(
        context,
        value: 'remove_folder',
        icon: Icons.folder_off,
        label: 'Remove from Folder',
        iconColor: AppColors.porchAmberOf(context),
        labelColor: AppColors.porchAmberOf(context),
      ),
    homeCardMenuItem(
      context,
      value: 'delete',
      icon: Icons.delete,
      label: 'Delete',
      iconColor: AppColors.negativeAccentOf(context),
      labelColor: AppColors.negativeAccentOf(context),
    ),
  ];
}

/// Group card right-click menu (same ordering rule as character cards).
List<PopupMenuItem<String>> groupCardMenuItems(
  BuildContext context, {
  required bool inFolder,
}) {
  return [
    homeCardMenuItem(
      context,
      value: 'new_chat',
      icon: Icons.add_comment_outlined,
      label: 'Start New Chat',
      iconColor: AppColors.porchAmberOf(context),
    ),
    homeCardMenuItem(
      context,
      value: 'chat_history',
      icon: Icons.history,
      label: 'Manage Chats',
    ),
    homeCardMenuItem(
      context,
      value: 'edit',
      icon: Icons.edit,
      label: 'Edit Group',
    ),
    homeCardMenuItem(
      context,
      value: 'duplicate',
      icon: Icons.copy,
      label: 'Duplicate Group',
    ),
    homeCardMenuItem(
      context,
      value: 'export',
      icon: Icons.upload,
      label: 'Export PNG',
    ),
    homeCardMenuItem(
      context,
      value: 'extract',
      icon: Icons.call_split,
      label: 'Extract Characters',
      iconColor: AppColors.journalAccentOf(context),
    ),
    homeCardMenuItem(
      context,
      value: 'move_folder',
      icon: Icons.drive_file_move,
      label: 'Move to Folder',
      iconColor: AppColors.porchAmberOf(context),
    ),
    if (inFolder)
      homeCardMenuItem(
        context,
        value: 'remove_folder',
        icon: Icons.folder_off,
        label: 'Remove from Folder',
        iconColor: AppColors.porchAmberOf(context),
        labelColor: AppColors.porchAmberOf(context),
      ),
    homeCardMenuItem(
      context,
      value: 'delete',
      icon: Icons.delete,
      label: 'Delete',
      iconColor: AppColors.negativeAccentOf(context),
      labelColor: AppColors.negativeAccentOf(context),
    ),
  ];
}
