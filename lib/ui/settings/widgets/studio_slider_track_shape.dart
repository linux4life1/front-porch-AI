// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Custom slider track shape for Generation settings:
/// - Highlights danger boundary zones in red (AppColors.negativeAccentOf).
/// - Paints a clean graphical default indicator pip directly on the track.
class StudioSliderTrackShape extends RoundedRectSliderTrackShape {
  const StudioSliderTrackShape({
    required this.min,
    required this.max,
    required this.defaultVal,
    this.dangerMin,
    this.dangerMax,
    required this.context,
  });

  final double min;
  final double max;
  final double defaultVal;
  final double? dangerMin;
  final double? dangerMax;
  final BuildContext context;

  double get normalizedDefault =>
      max > min ? ((defaultVal - min) / (max - min)).clamp(0.0, 1.0) : 0.0;

  double? get normalizedDangerMin => dangerMin != null && max > min
      ? ((dangerMin! - min) / (max - min)).clamp(0.0, 1.0)
      : null;

  double? get normalizedDangerMax => dangerMax != null && max > min
      ? ((dangerMax! - min) / (max - min)).clamp(0.0, 1.0)
      : null;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    if (sliderTheme.trackHeight == null || sliderTheme.trackHeight! <= 0) {
      return;
    }

    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final double trackLeft = trackRect.left;
    final double trackRight = trackRect.right;
    final double trackWidth = trackRight - trackLeft;

    final baseInactivePaint = Paint()
      ..color = sliderTheme.inactiveTrackColor ??
          AppColors.hairlineOf(this.context, 0.2);

    final dangerInactivePaint = Paint()
      ..color = AppColors.negativeAccentOf(this.context).withValues(alpha: 0.35);

    final baseActivePaint = Paint()
      ..color = sliderTheme.activeTrackColor ??
          AppColors.formAccentOf(this.context);

    final dangerActivePaint = Paint()
      ..color = AppColors.negativeAccentOf(this.context);

    final dMinNorm = normalizedDangerMin;
    final dMaxNorm = normalizedDangerMax;
    final dMinX = dMinNorm != null ? trackLeft + dMinNorm * trackWidth : null;
    final dMaxX = dMaxNorm != null ? trackLeft + dMaxNorm * trackWidth : null;

    final Canvas canvas = context.canvas;
    final Radius trackRadius = Radius.circular(trackRect.height / 2);

    // 1. Paint inactive track base & danger segments
    // Clip whole track to rounded rectangle bounds
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(trackRect, trackRadius));

    // Base inactive background
    canvas.drawRect(trackRect, baseInactivePaint);

    // Left danger zone (below dangerMin)
    if (dMinX != null && dMinX > trackLeft) {
      canvas.drawRect(
        Rect.fromLTRB(trackLeft, trackRect.top, dMinX, trackRect.bottom),
        dangerInactivePaint,
      );
    }

    // Right danger zone (above dangerMax)
    if (dMaxX != null && dMaxX < trackRight) {
      canvas.drawRect(
        Rect.fromLTRB(dMaxX, trackRect.top, trackRight, trackRect.bottom),
        dangerInactivePaint,
      );
    }

    // 2. Paint active track (up to thumb)
    final double thumbX = thumbCenter.dx.clamp(trackLeft, trackRight);

    // Left danger active segment
    if (dMinX != null) {
      final double activeDangerLeft = math.min(thumbX, dMinX);
      if (activeDangerLeft > trackLeft) {
        canvas.drawRect(
          Rect.fromLTRB(trackLeft, trackRect.top, activeDangerLeft, trackRect.bottom),
          dangerActivePaint,
        );
      }
    }

    // Safe active segment
    final double safeStart = dMinX != null ? math.max(trackLeft, dMinX) : trackLeft;
    final double safeEnd = dMaxX != null ? math.min(thumbX, dMaxX) : thumbX;
    if (thumbX > safeStart) {
      canvas.drawRect(
        Rect.fromLTRB(safeStart, trackRect.top, safeEnd, trackRect.bottom),
        baseActivePaint,
      );
    }

    // Right danger active segment
    if (dMaxX != null && thumbX > dMaxX) {
      canvas.drawRect(
        Rect.fromLTRB(dMaxX, trackRect.top, thumbX, trackRect.bottom),
        dangerActivePaint,
      );
    }

    canvas.restore();

    // 3. Paint Graphical Default Pip (indicator notch)
    final double defX = trackLeft + normalizedDefault * trackWidth;
    final double pipHeight = trackRect.height + 8.0;
    final Rect pipRect = Rect.fromCenter(
      center: Offset(defX, trackRect.center.dy),
      width: 2.5,
      height: pipHeight,
    );

    final Paint pipPaint = Paint()
      ..color = AppColors.textSecondary(this.context).withValues(alpha: 0.75);

    canvas.drawRRect(
      RRect.fromRectAndRadius(pipRect, const Radius.circular(1.25)),
      pipPaint,
    );
  }
}
