// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Custom slider track shape for Generation settings:
/// - Highlights danger boundary zones in red.
/// - Paints a clean graphical default indicator pip directly on the track.
/// - Supports RTL text directions and disabled states without retaining BuildContext.
class StudioSliderTrackShape extends RoundedRectSliderTrackShape {
  const StudioSliderTrackShape({
    required this.min,
    required this.max,
    required this.defaultVal,
    this.dangerMin,
    this.dangerMax,
    this.dangerActiveColor,
    this.dangerInactiveColor,
    this.pipColor,
  });

  final double min;
  final double max;
  final double defaultVal;
  final double? dangerMin;
  final double? dangerMax;
  final Color? dangerActiveColor;
  final Color? dangerInactiveColor;
  final Color? pipColor;

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
    final bool isRtl = textDirection == TextDirection.rtl;

    final double opacity = isEnabled ? 1.0 : 0.38;

    final Color baseInactiveColor = (isEnabled
            ? sliderTheme.inactiveTrackColor
            : sliderTheme.disabledInactiveTrackColor) ??
        Colors.grey.withValues(alpha: 0.3);

    final Color baseActiveColor = (isEnabled
            ? sliderTheme.activeTrackColor
            : sliderTheme.disabledActiveTrackColor) ??
        Colors.blue;

    final Color effectiveDangerActive =
        (dangerActiveColor ?? Colors.redAccent).withValues(alpha: opacity);
    final Color effectiveDangerInactive =
        (dangerInactiveColor ?? Colors.redAccent.withValues(alpha: 0.35))
            .withValues(alpha: opacity);
    final Color effectivePipColor =
        (pipColor ?? Colors.grey).withValues(alpha: isEnabled ? 0.75 : 0.38);

    final baseInactivePaint = Paint()
      ..color = baseInactiveColor.withValues(alpha: baseInactiveColor.a * opacity);
    final dangerInactivePaint = Paint()..color = effectiveDangerInactive;
    final baseActivePaint = Paint()
      ..color = baseActiveColor.withValues(alpha: baseActiveColor.a * opacity);
    final dangerActivePaint = Paint()..color = effectiveDangerActive;

    // Helper to map normalized [0, 1] value to canvas X coordinate
    double toX(double normalized) {
      final clamped = normalized.clamp(0.0, 1.0);
      return isRtl
          ? trackRight - clamped * trackWidth
          : trackLeft + clamped * trackWidth;
    }

    final dMinNorm = normalizedDangerMin;
    final dMaxNorm = normalizedDangerMax;
    final double? dMinX = dMinNorm != null ? toX(dMinNorm) : null;
    final double? dMaxX = dMaxNorm != null ? toX(dMaxNorm) : null;

    final Canvas canvas = context.canvas;
    final Radius trackRadius = Radius.circular(trackRect.height / 2);

    // 1. Paint inactive track base & danger segments
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(trackRect, trackRadius));

    // Base inactive background
    canvas.drawRect(trackRect, baseInactivePaint);

    // Danger zone inactive backgrounds
    if (dMinNorm != null && dMinX != null) {
      final double x1 = isRtl ? dMinX : trackLeft;
      final double x2 = isRtl ? trackRight : dMinX;
      if (x2 > x1) {
        canvas.drawRect(
          Rect.fromLTRB(x1, trackRect.top, x2, trackRect.bottom),
          dangerInactivePaint,
        );
      }
    }

    if (dMaxNorm != null && dMaxX != null) {
      final double x1 = isRtl ? trackLeft : dMaxX;
      final double x2 = isRtl ? dMaxX : trackRight;
      if (x2 > x1) {
        canvas.drawRect(
          Rect.fromLTRB(x1, trackRect.top, x2, trackRect.bottom),
          dangerInactivePaint,
        );
      }
    }

    // 2. Paint active track (from min origin up to thumb)
    final double thumbX = thumbCenter.dx.clamp(trackLeft, trackRight);

    if (!isRtl) {
      // LTR: track runs from trackLeft to trackRight
      // Left danger active segment (below dangerMin)
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
      if (safeEnd > safeStart) {
        canvas.drawRect(
          Rect.fromLTRB(safeStart, trackRect.top, safeEnd, trackRect.bottom),
          baseActivePaint,
        );
      }

      // Right danger active segment (above dangerMax)
      if (dMaxX != null && thumbX > dMaxX) {
        canvas.drawRect(
          Rect.fromLTRB(dMaxX, trackRect.top, thumbX, trackRect.bottom),
          dangerActivePaint,
        );
      }
    } else {
      // RTL: track runs from trackRight down to trackLeft
      // Low values are near trackRight (dangerMin if present is between dMinX and trackRight)
      if (dMinX != null) {
        final double activeDangerRight = math.max(thumbX, dMinX);
        if (activeDangerRight < trackRight) {
          canvas.drawRect(
            Rect.fromLTRB(activeDangerRight, trackRect.top, trackRight, trackRect.bottom),
            dangerActivePaint,
          );
        }
      }

      // Safe active segment
      final double safeStart = dMinX != null ? math.min(trackRight, dMinX) : trackRight;
      final double safeEnd = dMaxX != null ? math.max(thumbX, dMaxX) : thumbX;
      if (safeStart > safeEnd) {
        canvas.drawRect(
          Rect.fromLTRB(safeEnd, trackRect.top, safeStart, trackRect.bottom),
          baseActivePaint,
        );
      }

      // High danger active segment (above dangerMax, between trackLeft and dMaxX)
      if (dMaxX != null && thumbX < dMaxX) {
        canvas.drawRect(
          Rect.fromLTRB(thumbX, trackRect.top, dMaxX, trackRect.bottom),
          dangerActivePaint,
        );
      }
    }

    canvas.restore();

    // 3. Paint Graphical Default Pip (indicator notch)
    final double defX = toX(normalizedDefault);
    final double pipHeight = trackRect.height + 8.0;
    final Rect pipRect = Rect.fromCenter(
      center: Offset(defX, trackRect.center.dy),
      width: 2.5,
      height: pipHeight,
    );

    final Paint pipPaint = Paint()..color = effectivePipColor;

    canvas.drawRRect(
      RRect.fromRectAndRadius(pipRect, const Radius.circular(1.25)),
      pipPaint,
    );
  }
}
