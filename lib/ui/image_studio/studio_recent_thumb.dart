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

import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// What a Recent picture's menu can do.
enum StudioRecentAction { restore, keep, edit, delete }

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// The caption under a Recent picture: a clock time today, "Yesterday", or a
/// date. [now] comes from the caller so the wording is testable.
String studioRecentStamp(DateTime at, DateTime now) {
  final day = DateTime(at.year, at.month, at.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = today.difference(day).inDays;
  if (days == 0) {
    final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final m = at.minute.toString().padLeft(2, '0');
    return '$h:$m ${at.hour < 12 ? 'am' : 'pm'}';
  }
  if (days == 1) return 'Yesterday';
  return '${_months[at.month - 1]} ${at.day}';
}

/// One picture on the Recent shelf. Tap brings it back; right-click or
/// long-press opens [StudioRecentAction]s.
class StudioRecentThumb extends StatelessWidget {
  const StudioRecentThumb({
    super.key,
    required this.entry,
    required this.now,
    required this.selected,
    required this.canEdit,
    required this.onAction,
  });

  final StudioRecentEntry entry;
  final DateTime now;
  final bool selected;

  /// Whether the menu offers "Edit this picture".
  final bool canEdit;
  final ValueChanged<StudioRecentAction> onAction;

  Future<void> _menu(BuildContext context, Offset at) async {
    final picked = await showMenu<StudioRecentAction>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        const PopupMenuItem(
          value: StudioRecentAction.restore,
          child: Text('Bring back with its prompt'),
        ),
        PopupMenuItem(
          value: StudioRecentAction.keep,
          child: Text(entry.kept ? 'Unstar' : 'Star (never trim)'),
        ),
        if (canEdit)
          const PopupMenuItem(
            value: StudioRecentAction.edit,
            child: Text('Edit this picture'),
          ),
        const PopupMenuItem(
          value: StudioRecentAction.delete,
          child: Text('Delete'),
        ),
      ],
    );
    if (picked != null) onAction(picked);
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.formAccentOf(context);
    final caption =
        '${entry.mode == 'edit' ? 'Edit · ' : ''}'
        '${studioRecentStamp(entry.createdAt, now)}';
    return Tooltip(
      message: entry.prompt.isEmpty ? caption : entry.prompt,
      waitDuration: const Duration(milliseconds: 600),
      child: GestureDetector(
        onTap: () => onAction(StudioRecentAction.restore),
        onSecondaryTapDown: (d) => _menu(context, d.globalPosition),
        onLongPressStart: (d) => _menu(context, d.globalPosition),
        child: Container(
          key: ValueKey('studio-recent-${entry.name}'),
          width: 72,
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? accent : AppColors.borderOf(context),
              width: selected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                // Strip thumbnails decode small, not at generation size.
                child: Image.file(
                  File(entry.path),
                  fit: BoxFit.cover,
                  cacheWidth: 192,
                  errorBuilder: (context, error, stack) =>
                      const SizedBox.shrink(),
                ),
              ),
              if (entry.kept)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Icon(Icons.star, size: 14, color: accent),
                ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: AppColors.resolve(
                    context,
                    AppColors.background,
                    AppColors.lightBorder,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 9,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
