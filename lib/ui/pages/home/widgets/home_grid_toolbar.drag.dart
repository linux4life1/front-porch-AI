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
// along with Front Porch AI. If not, see https://www.gnu.org/licenses/.

part of 'home_grid_toolbar.dart';

/// The toolbar while a card or the picks are being dragged (library
/// phase 3), as in the approved sketch: the path, each level of it a drop
/// target, and a hint; sort, refresh and New Folder stay on the right.
extension _HomeGridToolbarDrag on HomeGridToolbar {
  Widget _dragRow(BuildContext context, double width) {
    final inFolder = activeFolderId != null;
    final room = width - 560;
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              if (inFolder) ...[
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Up one level',
                  visualDensity: VisualDensity.compact,
                  onPressed: onFolderNavigateBack,
                ),
                const SizedBox(width: 8),
                Flexible(child: _breadcrumb(context, dropTargets: true)),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  inFolder
                      ? 'Drop on a folder, or on a level of the path'
                      : 'Drop on a folder',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (room >= 96) ...[
          const SizedBox(width: 12),
          _sortControl(context, labeled: room >= 240),
          IconButton(
            tooltip: 'Refresh character list',
            icon: const Icon(Icons.refresh),
            visualDensity: VisualDensity.compact,
            onPressed: () => repo.loadCharacters(),
          ),
          IconButton(
            tooltip: inFolder ? 'New Subfolder' : 'New Folder',
            icon: Icon(
              Icons.create_new_folder_outlined,
              color: inFolder ? AppColors.porchAmberOf(context) : null,
            ),
            visualDensity: VisualDensity.compact,
            onPressed: () => onFolderDialogAction(
              FolderDialogAction.create,
              parentId: activeFolderId,
            ),
          ),
        ],
      ],
    );
  }

  /// One level of the path as a drop target: a dashed amber outline and a
  /// light amber fill while the drag is live, solid once something hovers.
  Widget _levelTarget(BuildContext context, String label, String? folderId) {
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
