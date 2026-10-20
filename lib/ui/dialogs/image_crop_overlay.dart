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

import 'package:front_porch_ai/utils/utils.dart';

/// Painters for [ImageCropDialog] (extracted 2026-08-14 when presets, fill
/// choices and the circle guide pushed the dialog past the size cap).

/// The stage base: previews exactly what an overhanging crop saves as fill —
/// a solid color, or a checkerboard for [CropFill.transparent]. Image data,
/// not theme chrome, so the swatch colors come from [CropFill] itself.
class CropFillBasePainter extends CustomPainter {
  const CropFillBasePainter(this.fill);

  final CropFill fill;

  @override
  void paint(Canvas canvas, Size size) {
    if (fill != CropFill.transparent) {
      canvas.drawRect(Offset.zero & size, Paint()..color = fill.color);
      return;
    }
    // Checkerboard — the universal "this will be transparent" preview.
    const cell = 10.0;
    // theme-keep: the transparency checkerboard is the same in every theme.
    final light = Paint()..color = const Color(0xFFBDBDBD);
    // theme-keep: the transparency checkerboard is the same in every theme.
    final dark = Paint()..color = const Color(0xFF8E8E8E);
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = 0; x * cell < size.width; x++) {
        canvas.drawRect(
          Rect.fromLTWH(x * cell, y * cell, cell, cell),
          (x + y).isEven ? light : dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(CropFillBasePainter old) => old.fill != fill;
}

/// Scrim outside the crop box + amber border, thirds guides, the grab
/// handles (corners only under a locked aspect), and the optional circular
/// face guide.
class CropOverlayPainter extends CustomPainter {
  const CropOverlayPainter({
    required this.cropVp,
    required this.accent,
    required this.scrim,
    required this.showEdgeHandles,
    required this.circleGuide,
  });

  final Rect cropVp;
  final Color accent;
  final Color scrim;
  final bool showEdgeHandles;
  final bool circleGuide;

  @override
  void paint(Canvas canvas, Size size) {
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRect(cropVp),
    );
    canvas.drawPath(outside, Paint()..color = scrim);

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = accent;
    canvas.drawRect(cropVp, border);

    final guide = Paint()
      ..strokeWidth = 0.75
      ..color = accent.withValues(alpha: 0.35);
    for (var i = 1; i <= 2; i++) {
      final x = cropVp.left + cropVp.width * i / 3;
      final y = cropVp.top + cropVp.height * i / 3;
      canvas.drawLine(Offset(x, cropVp.top), Offset(x, cropVp.bottom), guide);
      canvas.drawLine(Offset(cropVp.left, y), Offset(cropVp.right, y), guide);
    }

    if (circleGuide) {
      canvas.drawOval(
        cropVp,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = accent.withValues(alpha: 0.7),
      );
    }

    final dot = Paint()..color = accent;
    final corners = [
      cropVp.topLeft,
      cropVp.topRight,
      cropVp.bottomLeft,
      cropVp.bottomRight,
    ];
    final edges = [
      cropVp.topCenter,
      cropVp.centerLeft,
      cropVp.centerRight,
      cropVp.bottomCenter,
    ];
    for (final c in [...corners, if (showEdgeHandles) ...edges]) {
      canvas.drawCircle(c, 5, dot);
    }
  }

  @override
  bool shouldRepaint(CropOverlayPainter old) =>
      old.cropVp != cropVp ||
      old.accent != accent ||
      old.scrim != scrim ||
      old.showEdgeHandles != showEdgeHandles ||
      old.circleGuide != circleGuide;
}
