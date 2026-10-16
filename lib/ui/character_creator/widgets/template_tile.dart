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

import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/creator_dashed_outline.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

enum _TileAction { load, rename, delete }

/// One template on the Mode step's picker (docs/design/creator-ui-spec.md,
/// "Template picker card"): its name, its summary line, and `Saved {d Mon}`
/// with a ⋯ menu for yours, or the `Built in` pill for an archetype. A file
/// that cannot be read says so and offers only Delete.
class TemplateTile extends StatelessWidget {
  const TemplateTile({
    super.key,
    required this.template,
    required this.selected,
    required this.onLoad,
    this.onRename,
    this.onDelete,
    this.now,
  });

  final CreatorTemplate template;

  /// The form was started from this one: a 1.5px amber border.
  final bool selected;
  final VoidCallback onLoad;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  /// "Now" for the saved label's year; a test pins it.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final t = template;
    final amber = StudioColors.amberOf(context);
    final saved = t.savedAt;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: t.broken ? null : onLoad,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: StudioColors.bgOf(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? amber : StudioColors.lineOf(context),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 6,
                  children: [
                    // The ⋯ button sits 4px up and 6px out of this row.
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 24),
                      child: Padding(
                        padding: EdgeInsets.only(right: t.builtIn ? 0 : 28),
                        child: Semantics(
                          button: !t.broken,
                          child: Text(
                            t.name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                              color: StudioColors.inkOf(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Text(
                      templateSummaryLine(t),
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: StudioColors.mutedOf(context),
                      ),
                    ),
                    if (t.builtIn)
                      const BuiltInPill()
                    else if (saved != null)
                      Text(
                        templateSavedLabel(saved, now: now ?? DateTime.now()),
                        style: TextStyle(
                          fontSize: 11,
                          color: StudioColors.faintOf(context),
                        ),
                      ),
                  ],
                ),
              ),
              if (!t.builtIn)
                Positioned(top: 8, right: 6, child: _menu(context, t)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menu(BuildContext context, CreatorTemplate t) {
    final ink = StudioColors.inkOf(context);
    PopupMenuItem<_TileAction> item(_TileAction a, String label, Color fg) =>
        PopupMenuItem<_TileAction>(
          value: a,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(label, style: TextStyle(fontSize: 14, color: fg)),
        );
    return SizedBox.square(
      dimension: 28,
      child: PopupMenuButton<_TileAction>(
        key: ValueKey('template-menu-${t.slug}'),
        tooltip: 'More for ${t.name}',
        padding: EdgeInsets.zero,
        iconSize: 16,
        icon: Icon(Icons.more_horiz, color: StudioColors.mutedOf(context)),
        style: IconButton.styleFrom(
          minimumSize: const Size.square(28),
          shape: const CircleBorder(),
        ),
        // The sketch hangs the 150px menu from the tile's right edge, 4px
        // past it: 111px left of this button's own left edge.
        position: PopupMenuPosition.under,
        offset: const Offset(-111, -1),
        menuPadding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(minWidth: 150, maxWidth: 150),
        onSelected: (a) => switch (a) {
          _TileAction.load => onLoad(),
          _TileAction.rename => onRename?.call(),
          _TileAction.delete => onDelete?.call(),
        },
        itemBuilder: (_) => [
          if (!t.broken) ...[
            item(_TileAction.load, 'Load', ink),
            item(_TileAction.rename, 'Rename', ink),
          ],
          item(_TileAction.delete, 'Delete', StudioColors.badOf(context)),
        ],
      ),
    );
  }
}

/// Tiles in 12px-gap rows that wrap, each row as tall as its tallest tile,
/// as the sketch's flex row draws them. A tile is [maxWidth] wide and gives
/// up to [maxWidth] - [minWidth] to fit one more in the row.
class TemplateTileGrid extends StatelessWidget {
  const TemplateTileGrid({
    super.key,
    required this.tiles,
    this.maxWidth = 176,
    this.minWidth = 168,
  });

  final List<Widget> tiles;
  final double maxWidth;
  final double minWidth;

  static const _gap = 12.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final width = box.maxWidth;
      final perRow = ((width + _gap) / (minWidth + _gap)).floor().clamp(
        1,
        tiles.length,
      );
      final tileWidth = ((width - _gap * (perRow - 1)) / perRow).clamp(
        0.0,
        maxWidth,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: _gap,
        children: [
          for (var i = 0; i < tiles.length; i += perRow)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: _gap,
                children: [
                  for (final tile in tiles.skip(i).take(perRow))
                    SizedBox(width: tileWidth, child: tile),
                ],
              ),
            ),
        ],
      );
    },
  );
}

/// `Built in`: 11 / 600 amber in a 1px amber-at-50% outline, radius 8.
class BuiltInPill extends StatelessWidget {
  const BuiltInPill({super.key});

  @override
  Widget build(BuildContext context) {
    final amber = StudioColors.amberOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: amber.withValues(alpha: 0.5)),
      ),
      child: Text(
        'Built in',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: amber,
        ),
      ),
    );
  }
}

/// The picker's last tile: `All 15 built in ›` over a muted line, in a
/// dashed `lineStrong` outline. Opens the built-ins picker.
class AllBuiltInsTile extends StatelessWidget {
  const AllBuiltInsTile({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final amber = StudioColors.amberOf(context);
    return CustomPaint(
      foregroundPainter: CreatorDashedOutline(
        color: StudioColors.lineStrongOf(context),
        radius: 12,
        width: 1,
        dash: 3,
        gap: 3,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const ValueKey('template-all-built-ins'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    Text(
                      kAllBuiltInLabel,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: amber,
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 16, color: amber),
                  ],
                ),
                Text(
                  'Yandere, Femme Fatale, Dark Lord and the rest',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: StudioColors.mutedOf(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
