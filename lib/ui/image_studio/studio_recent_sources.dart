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

import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/theme/ink_colors.dart';

import 'studio_recent_thumb.dart' show studioRecentStamp;

/// The line icon for each source: the shelf's marks and the line on the
/// picture on show use the same one (the phone draws the same shapes).
IconData studioSourceIcon(ImageSourceKind kind) => switch (kind) {
  ImageSourceKind.studio => Icons.auto_awesome_outlined,
  ImageSourceKind.edit => Icons.edit_outlined,
  ImageSourceKind.creator => Icons.person_add_alt_outlined,
  ImageSourceKind.chat => Icons.chat_bubble_outline,
  ImageSourceKind.guest => Icons.door_front_door_outlined,
  ImageSourceKind.story => Icons.menu_book_outlined,
};

/// The Recent shelf's source chips: All, then every source in a fixed order,
/// each with its count. A source with no pictures keeps its chip, disabled,
/// so the row never moves. [selected] null is All.
class StudioRecentSourceChips extends StatelessWidget {
  const StudioRecentSourceChips({
    super.key,
    required this.entries,
    required this.selected,
    required this.onSelected,
  });

  final List<StudioRecentEntry> entries;
  final ImageSourceKind? selected;
  final ValueChanged<ImageSourceKind?> onSelected;

  @override
  Widget build(BuildContext context) {
    int count(ImageSourceKind k) => entries.where((e) => e.source == k).length;
    return SingleChildScrollView(
      key: const Key('studio-recent-sources'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip(context, null, 'All', entries.length),
          for (final kind in ImageSourceKind.values)
            _chip(context, kind, kind.label, count(kind)),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    ImageSourceKind? kind,
    String label,
    int count,
  ) {
    final on = kind == selected;
    final accent = AppColors.formAccentOf(context);
    final enabled = on || kind == null || count > 0;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        key: Key('studio-recent-source-${kind?.key ?? 'all'}'),
        showCheckmark: false,
        selected: on,
        onSelected: enabled ? (_) => onSelected(kind) : null,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        shape: StadiumBorder(
          side: BorderSide(
            color: on ? accent : AppColors.borderOf(context),
            width: on ? 1.5 : 1,
          ),
        ),
        color: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accent.withValues(alpha: 0.16)
              : Colors.transparent,
        ),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                color: on ? accent : AppColors.textPrimary(context),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Where the picture on show came from, laid along its bottom edge: the
/// source's icon, "Character creator · Ada" and when. Shown over the picture
/// only; the picture itself is never changed.
class StudioSourceLine extends StatelessWidget {
  const StudioSourceLine({super.key, required this.entry, this.now});

  final StudioRecentEntry entry;

  /// "Now" for the time wording; the real clock when null.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: InkColors.onImage,
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 1.3,
    );
    return Container(
      key: const Key('studio-source-line'),
      color: InkColors.dim(0.66),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        children: [
          Icon(
            studioSourceIcon(entry.source),
            size: 14,
            color: InkColors.onImage,
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(entry.sourceLine, style: style, maxLines: 2)),
          const SizedBox(width: 8),
          Text(
            studioRecentStamp(entry.createdAt, now ?? DateTime.now()),
            style: style,
          ),
        ],
      ),
    );
  }
}
