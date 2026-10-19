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

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/home/cards/library_drag_payload.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Clickable path — "My Characters / … / parent / current". Every segment
/// but the current one jumps straight there, so deep nesting never needs N
/// back-taps to escape.
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
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: crumbStyle,
              ),
            ),
          );
    final separator = Text(
      '/',
      style: TextStyle(color: AppColors.textTertiary(context)),
    );
    // Deep paths keep the top level and the parent; the levels between fold
    // into one "…" that jumps to the deepest of them.
    final ancestors = trail.isEmpty
        ? const <CharacterFolder>[]
        : trail.sublist(0, trail.length - 1);
    final hidden = ancestors.length > 1
        ? ancestors.sublist(0, ancestors.length - 1)
        : const <CharacterFolder>[];
    final parent = ancestors.isEmpty ? null : ancestors.last;
    final current = trail.isEmpty ? null : trail.last;
    final named = parent == null ? 1 : 2;
    return LayoutBuilder(
      builder: (context, constraints) {
        // The folder you're standing in is laid out first. It keeps all but
        // a floor for each level above it, and never less than 40% of the
        // row, so the levels above ellipsize ("My… / Bletchfi…") and never
        // collapse to nothing or slide under the back arrow.
        final width = constraints.maxWidth;
        final currentMax = width.isFinite
            ? math.max(
                width - named * _kCrumbFloor - (hidden.isEmpty ? 0 : 28),
                width * 0.4,
              )
            : double.infinity;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: crumb('My Characters', null)),
            if (hidden.isNotEmpty) ...[
              separator,
              _HiddenLevels(
                names: [for (final f in hidden) f.name],
                onTap: dropTargets ? null : () => onFolderJump(hidden.last.id),
                style: crumbStyle,
              ),
            ],
            if (parent != null) ...[
              separator,
              Flexible(child: crumb(parent.name, parent.id)),
            ],
            if (current != null) ...[
              separator,
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: currentMax),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    current.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Room each level above the current folder is promised: "My…" plus its
/// padding and separator.
const _kCrumbFloor = 64.0;

/// The "…" standing in for folded middle levels. Hovering names them; a tap
/// jumps to the deepest. While a drag is live it is only a marker.
class _HiddenLevels extends StatelessWidget {
  const _HiddenLevels({
    required this.names,
    required this.onTap,
    required this.style,
  });

  final List<String> names;
  final VoidCallback? onTap;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: names.join(' / '),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text('…', style: style),
        ),
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
            decoration: BoxDecoration(
              color: amber.withValues(alpha: over ? 0.15 : 0.10),
              borderRadius: BorderRadius.circular(8),
              border: over ? Border.all(color: amber, width: 2) : null,
            ),
            // widthFactor keeps the pill hugging its label inside the
            // breadcrumb's Flexible instead of stretching to the share.
            child: Align(
              widthFactor: 1,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: amber,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
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
