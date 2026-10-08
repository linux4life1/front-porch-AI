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

/// What follows the pointer when a held, picked card drags the whole
/// selection (library phase 3): the pressed card's small frame with two
/// frames stacked behind it and a terracotta count badge.
class LibraryDragGhost extends StatelessWidget {
  const LibraryDragGhost({
    super.key,
    required this.count,
    required this.name,
    required this.cover,
  });

  final int count;
  final String name;

  /// The pressed card's picture (or its placeholder icon).
  final Widget cover;

  static const double _frameW = 124;
  static const double _frameH = 168;
  static const double _over = 24; // room above and right for the badge

  /// The pointer sits near the front frame's lower right corner.
  static Offset anchor(
    Draggable<Object> draggable,
    BuildContext context,
    Offset position,
  ) => const Offset(94, _over + 134);

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.porchTerracottaOf(context);
    Widget frame({
      required Color fill,
      required Color border,
      required double width,
      List<BoxShadow>? shadow,
      Widget? child,
    }) => Container(
      width: _frameW,
      height: _frameH,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: width),
        boxShadow: shadow,
      ),
      child: child,
    );
    final back = AppColors.surfaceContainerOf(context);
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        key: const Key('library-drag-ghost'),
        width: _frameW + _over,
        height: _frameH + _over,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 14,
              top: _over - 12,
              child: frame(
                fill: back,
                border: accent.withValues(alpha: 0.7),
                width: 2,
              ),
            ),
            Positioned(
              left: 7,
              top: _over - 6,
              child: frame(
                fill: back,
                border: accent.withValues(alpha: 0.8),
                width: 2,
              ),
            ),
            Positioned(
              left: 0,
              top: _over,
              child: frame(
                fill: AppColors.cardOf(context),
                border: accent,
                width: 2.5,
                shadow: [
                  BoxShadow(
                    color: AppColors.resolve(
                      context,
                      Colors.black.withValues(alpha: 0.5),
                      Colors.black.withValues(alpha: 0.25),
                    ),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: cover),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: _frameW + _over - 30,
              top: 0,
              child: Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.resolve(
                        context,
                        Colors.black.withValues(alpha: 0.4),
                        Colors.black.withValues(alpha: 0.2),
                      ),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    // Dark on the dark theme's light terracotta (the
                    // sketch), white on the light theme's deep one.
                    color: AppColors.resolve(
                      context,
                      AppColors.onChaosAccent,
                      AppColors.userTextLight,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
