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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/home/cards/library_drag_payload.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Clickable path — "My Characters / folder1 / folder2 / current". Every
/// segment but the current one jumps straight there, so deep nesting never
/// needs N back-taps to escape.
/// While a drag is live ([dropTargets]) every level but the current one
/// takes a drop instead (library phase 3).
class HomeToolbarBreadcrumb extends StatelessWidget {
  const HomeToolbarBreadcrumb({
    super.key,
    required this.activeFolderId,
    required this.folders,
    required this.onFolderJump,
    this.dropTargets = false,
    this.onDropOnLevel,
  });

  final String? activeFolderId;

  /// Every library folder ([FolderService.folders]).
  final List<CharacterFolder> folders;

  /// Breadcrumb jump — null = the library top level, else an ancestor folder.
  final void Function(String? folderId) onFolderJump;
  final bool dropTargets;

  /// A drop on a level of the path; null folder id is the top level.
  final void Function(Object item, String? folderId)? onDropOnLevel;

  /// Ancestor chain for the active folder, root-first with the current
  /// folder last (subfolder cards only render inside their parent, so the
  /// parent chain is the full navigation path).
  List<CharacterFolder> _trail() {
    final trail = <CharacterFolder>[];
    var cur = activeFolderId;
    while (cur != null) {
      final folder = folders.where((f) => f.id == cur).firstOrNull;
      if (folder == null) break;
      trail.insert(0, folder);
      cur = folder.parentId;
    }
    return trail;
  }

  @override
  Widget build(BuildContext context) {
    final trail = _trail();
    final crumbStyle = TextStyle(
      color: AppColors.textSecondary(context),
      fontSize: 15,
    );
    Widget crumb(String label, String? target) => dropTargets
        ? HomeToolbarLevelTarget(
            label: label,
            folderId: target,
            onDropOnLevel: onDropOnLevel,
          )
        : InkWell(
            onTap: () => onFolderJump(target),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(label, style: crumbStyle),
            ),
          );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      // Keep the tail (the folder you're standing in) visible on long paths.
      reverse: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          crumb('My Characters', null),
          for (var i = 0; i < trail.length; i++) ...[
            Text('/', style: TextStyle(color: AppColors.textTertiary(context))),
            if (i < trail.length - 1)
              crumb(trail[i].name, trail[i].id)
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  trail[i].name,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// One level of the path as a drop target: a dashed amber outline and a
/// light amber fill while the drag is live, solid once something hovers.
class HomeToolbarLevelTarget extends StatelessWidget {
  const HomeToolbarLevelTarget({
    super.key,
    required this.label,
    required this.folderId,
    required this.onDropOnLevel,
  });

  final String label;
  final String? folderId;
  final void Function(Object item, String? folderId)? onDropOnLevel;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) => libraryDragCount(details.data) > 0,
      onAcceptWithDetails: (details) =>
          onDropOnLevel?.call(details.data, folderId),
      builder: (context, candidates, _) {
        final over = candidates.isNotEmpty;
        return CustomPaint(
          foregroundPainter: over ? null : _DashedOutline(amber),
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: amber.withValues(alpha: over ? 0.15 : 0.10),
              borderRadius: BorderRadius.circular(8),
              border: over ? Border.all(color: amber, width: 2) : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                color: amber,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A 1.5 px dashed rounded outline (Flutter has no dashed border).
class _DashedOutline extends CustomPainter {
  _DashedOutline(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.75),
          const Radius.circular(8),
        ),
      );
    for (final metric in outline.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 7) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutline oldDelegate) => oldDelegate.color != color;
}
