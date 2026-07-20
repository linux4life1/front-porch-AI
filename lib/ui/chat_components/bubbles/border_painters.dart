import 'dart:math';
import 'package:flutter/material.dart';

abstract class ThemeBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  ThemeBorderPainter({required this.color, this.strokeWidth = 2.0});

  @override
  bool shouldRepaint(covariant ThemeBorderPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}

class ScallopedBorderPainter extends ThemeBorderPainter {
  ScallopedBorderPainter({required super.color, super.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final half = strokeWidth / 2;
    final path = Path();
    path.moveTo(half, half);
    const scallopCount = 8;
    final spacing = size.width / scallopCount;
    for (int i = 0; i < scallopCount; i++) {
      path.relativeQuadraticBezierTo(spacing / 4, -6, spacing / 2, 0);
    }
    path.lineTo(size.width - half, half);
    path.lineTo(size.width - half, size.height - half);
    path.lineTo(half, size.height - half);
    path.close();
    canvas.drawPath(path, paint);
  }
}

class DualLineBorderPainter extends ThemeBorderPainter {
  DualLineBorderPainter({required super.color, super.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final rect = Offset.zero & size;
    canvas.drawRect(rect.deflate(2), paint);
    canvas.drawRect(rect.deflate(6), paint);
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    for (double x = 8; x < size.width - 8; x += 20) {
      canvas.drawCircle(Offset(x, 4), 1.5, dotPaint);
      canvas.drawCircle(Offset(x, size.height - 4), 1.5, dotPaint);
    }
  }
}

class GridBorderPainter extends ThemeBorderPainter {
  GridBorderPainter({required super.color, super.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    for (double x = 0; x < size.width; x += 16) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 16) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rect = Offset.zero & size;
    canvas.drawRect(rect.deflate(1), borderPaint);
    for (double x = 4; x < size.width; x += 16) {
      canvas.drawCircle(Offset(x, 4), 1.5, borderPaint..style = PaintingStyle.fill);
    }
  }
}

class WavyBorderPainter extends ThemeBorderPainter {
  WavyBorderPainter({required super.color, super.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final path = Path();
    path.moveTo(0, 0);
    const waveCount = 6;
    final sw = size.width / waveCount;
    for (int i = 0; i < waveCount; i++) {
      path.relativeQuadraticBezierTo(sw / 4, -4, sw / 2, 0);
      path.relativeQuadraticBezierTo(sw / 4, 4, sw / 2, 0);
    }
    path.lineTo(size.width, size.height);
    for (int i = 0; i < waveCount; i++) {
      path.relativeQuadraticBezierTo(-sw / 4, 4, -sw / 2, 0);
      path.relativeQuadraticBezierTo(-sw / 4, -4, -sw / 2, 0);
    }
    path.close();
    canvas.drawPath(path, paint);
  }
}

class ShadowBorderPainter extends ThemeBorderPainter {
  ShadowBorderPainter({required super.color, super.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final rect = Rect.fromLTWH(3, 3, size.width, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      paint,
    );
    final border = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4)),
      border,
    );
  }
}

class VineBorderPainter extends ThemeBorderPainter {
  VineBorderPainter({required super.color, super.strokeWidth});

  /// Draws a stylized ivy leaf (tip up) into [path] centered at origin.
  void _addIvyLeaf(Path path, double size) {
    final s = size / 2;
    path.moveTo(0, -s);
    path.quadraticBezierTo(s * 0.6, -s * 0.6, s, -s * 0.1);
    path.quadraticBezierTo(s * 0.8, s * 0.1, s * 0.5, s * 0.3);
    path.quadraticBezierTo(s * 0.6, s * 0.5, s * 0.15, s * 0.6);
    path.quadraticBezierTo(0, s * 0.5, 0, s * 0.3);
    path.quadraticBezierTo(0, s * 0.5, -s * 0.15, s * 0.6);
    path.quadraticBezierTo(-s * 0.6, s * 0.5, -s * 0.5, s * 0.3);
    path.quadraticBezierTo(-s * 0.8, s * 0.1, -s, -s * 0.1);
    path.quadraticBezierTo(-s * 0.6, -s * 0.6, 0, -s);
    path.close();
  }

  /// Draws a random offshoot tendril from [origin], curling outward.
  /// The tendril is added to [path].
  void _addTendril(Path path, Offset origin, double dirAngle, double length, Random rng) {
    final mid = Offset(
      origin.dx + cos(dirAngle) * length * 0.5 + rng.nextDouble() * 6 - 3,
      origin.dy + sin(dirAngle) * length * 0.5 + rng.nextDouble() * 6 - 3,
    );
    final curlAngle = dirAngle + rng.nextDouble() * 1.5 - 0.75;
    final end = Offset(
      origin.dx + cos(dirAngle) * length + cos(curlAngle) * 4,
      origin.dy + sin(dirAngle) * length + sin(curlAngle) * 4,
    );
    path.moveTo(origin.dx, origin.dy);
    path.quadraticBezierTo(mid.dx, mid.dy, end.dx, end.dy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final vinePaint = Paint()
      ..color = const Color(0xFF5D4037)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 1.5;
    const inset = 8.0;
    final leafPaint = Paint()
      ..color = const Color(0xFF1B5E20)
      ..style = PaintingStyle.fill;

    final rng = Random(42);
    final edgeData = [
      (Offset(inset, inset), Offset(size.width - inset, inset), 0.0),
      (Offset(size.width - inset, inset), Offset(size.width - inset, size.height - inset), -pi / 2),
      (Offset(size.width - inset, size.height - inset), Offset(inset, size.height - inset), pi),
      (Offset(inset, size.height - inset), Offset(inset, inset), pi / 2),
    ];

    for (final (start, end, outwardAngle) in edgeData) {
      final path = Path();
      final offshootPath = Path();
      path.moveTo(start.dx, start.dy);
      final edgeLen = (start - end).distance;
      final segments = (edgeLen / 20).round().clamp(3, 30);
      final segLen = 1.0 / segments;
      for (int i = 0; i < segments; i++) {
        final t0 = i * segLen;
        final t1 = (i + 1) * segLen;
        final p0 = Offset.lerp(start, end, t0)!;
        final p1 = Offset.lerp(start, end, t1)!;

        // Random control point offset perpendicular to edge
        final perpOffset = rng.nextDouble() * 8 - 4;
        final cpx = (p0.dx + p1.dx) / 2 + cos(outwardAngle + pi / 2) * perpOffset;
        final cpy = (p0.dy + p1.dy) / 2 + sin(outwardAngle + pi / 2) * perpOffset;

        path.quadraticBezierTo(cpx, cpy, p1.dx, p1.dy);

        // Random offshoot tendril (~30% chance per segment)
        if (rng.nextDouble() < 0.3 && edgeLen > 40) {
          final midX = (p0.dx + p1.dx) / 2 + cos(outwardAngle + pi / 2) * perpOffset;
          final midY = (p0.dy + p1.dy) / 2 + sin(outwardAngle + pi / 2) * perpOffset;
          _addTendril(
            offshootPath,
            Offset(midX, midY),
            outwardAngle + (rng.nextDouble() - 0.5) * 0.8,
            8 + rng.nextDouble() * 12,
            rng,
          );
        }
      }
      canvas.drawPath(path, vinePaint);
      if (edgeLen > 40) {
        canvas.drawPath(offshootPath, vinePaint..strokeWidth = strokeWidth);
      }
      vinePaint.strokeWidth = strokeWidth * 1.5;

      final leafCount = (edgeLen / 70).round().clamp(1, 4);
      for (int i = 0; i < leafCount; i++) {
        final t = (i + 1) / (leafCount + 1);
        final segIdx = (t * segments).floor().clamp(0, segments - 1);
        final st = segIdx * segLen;
        final en = (segIdx + 1) * segLen;
        final p0 = Offset.lerp(start, end, st)!;
        final p1 = Offset.lerp(start, end, en)!;
        final midT = (t - st) / (en - st);
        final cx = p0.dx + (p1.dx - p0.dx) * midT;
        final cy = p0.dy + (p1.dy - p0.dy) * midT;
        final perpOff = (rng.nextDouble() - 0.5) * 2; // re-sync; actual vine offset unknown here
        final lx = cx + cos(outwardAngle + pi / 2) * perpOff * 4;
        final ly = cy + sin(outwardAngle + pi / 2) * perpOff * 4;

        final outward = i.isEven ? -1 : 1;
        final leafPath = Path();
        _addIvyLeaf(leafPath, 14);
        canvas.save();
        canvas.translate(lx, ly);
        canvas.rotate(outwardAngle + outward * pi / 4);
        canvas.drawPath(leafPath, leafPaint);
        canvas.restore();
      }
    }
  }
}

class WaveBorderPainter extends ThemeBorderPainter {
  WaveBorderPainter({required super.color, super.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    for (int row = 1; row <= 3; row++) {
      final y = size.height * row / 4;
      final path = Path();
      path.moveTo(0, y);
      for (double x = 0; x < size.width; x += 8) {
        path.lineTo(x, y + sin(x / 10) * 3);
      }
      canvas.drawPath(path, paint);
    }
    final border = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRect(Offset.zero & size, border);
  }
}

class GlitchBorderPainter extends ThemeBorderPainter {
  GlitchBorderPainter({required super.color, super.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(42);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final rect = Offset.zero & size;
    canvas.drawRect(rect, paint);
    paint.strokeWidth = 2.0;
    for (int i = 0; i < 3; i++) {
      final offset = rng.nextDouble() * 4 - 2;
      canvas.drawLine(
        Offset(rng.nextDouble() * size.width, 0),
        Offset(rng.nextDouble() * size.width, size.height),
        paint..strokeWidth = 0.5,
      );
      canvas.drawRect(
        rect.shift(Offset(offset, 0)).deflate(2),
        paint..strokeWidth = 1.0,
      );
    }
  }
}

class FloralBorderPainter extends ThemeBorderPainter {
  FloralBorderPainter({required super.color, super.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final corners = [
      Offset(4, 4),
      Offset(size.width - 4, 4),
      Offset(size.width - 4, size.height - 4),
      Offset(4, size.height - 4),
    ];
    for (final center in corners) {
      for (int r = 0; r < 3; r++) {
        canvas.drawCircle(center, 4.0 + r * 3.0, paint);
      }
      for (int angle = 0; angle < 360; angle += 45) {
        final rad = angle * pi / 180;
        final petalEnd = Offset(
          center.dx + cos(rad) * 5,
          center.dy + sin(rad) * 5,
        );
        canvas.drawLine(center, petalEnd, paint);
      }
      canvas.drawCircle(center, 1.5, paint..style = PaintingStyle.fill);
      paint.style = PaintingStyle.stroke;
    }
    final border = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawRect(Offset.zero & size, border);
  }
}

class GearBorderPainter extends ThemeBorderPainter {
  GearBorderPainter({required super.color, super.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final center = Offset(size.width / 2, size.height / 2);
    const pitchR = 50.0;
    const addendum = 8.0;
    const dedendum = 10.0;
    const outerR = pitchR + addendum;
    const rootR = pitchR - dedendum;
    const teeth = 10;
    const dist = 2 * pitchR;
    final triR = dist / sqrt(3);
    // With 3 identical gears in a triangle, only 2 of 3 pairs can mesh.
    // A-B and A-C get perfect half-pitch offset. B-C naturally align
    // but present valleys (not teeth) at the contact region.
    final offsets = [0.0, pi / teeth, pi / teeth];
    final positions = <Offset>[
      Offset(center.dx, center.dy - triR),
      Offset(center.dx + triR * cos(pi / 6), center.dy + triR * sin(pi / 6)),
      Offset(center.dx - triR * cos(pi / 6), center.dy + triR * sin(pi / 6)),
    ];

    for (int g = 0; g < positions.length; g++) {
      final pos = positions[g];
      final rot = offsets[g];
      final path = Path();
      const rootHW = pi * 0.55 / teeth;
      const tipHW = pi * 0.30 / teeth;
      for (int i = 0; i < teeth; i++) {
        final seg = i * 2 * pi / teeth + rot;
        final rootL = seg - rootHW;
        final rootR_ = seg + rootHW;
        final tipL = seg - tipHW;
        final tipR = seg + tipHW;
        final nextRootL = (i + 1) * 2 * pi / teeth + rot - rootHW;

        // Control point for involute curve (outward bulge at pitch radius)
        final ctrlAngle = (rootL + tipL) * 0.5 + pi * 0.015 / teeth;
        final ctrlR = pitchR * 1.04;

        if (i == 0) {
          path.moveTo(pos.dx + cos(rootL) * rootR, pos.dy + sin(rootL) * rootR);
        }
        // Left involute flank
        path.quadraticBezierTo(
          pos.dx + cos(ctrlAngle) * ctrlR,
          pos.dy + sin(ctrlAngle) * ctrlR,
          pos.dx + cos(tipL) * outerR,
          pos.dy + sin(tipL) * outerR,
        );
        // Flat tip
        path.lineTo(pos.dx + cos(tipR) * outerR, pos.dy + sin(tipR) * outerR);
        // Right involute flank
        final ctrlRAngle = (tipR + rootR_) * 0.5 - pi * 0.015 / teeth;
        path.quadraticBezierTo(
          pos.dx + cos(ctrlRAngle) * ctrlR,
          pos.dy + sin(ctrlRAngle) * ctrlR,
          pos.dx + cos(rootR_) * rootR,
          pos.dy + sin(rootR_) * rootR,
        );
        // Valley floor to next tooth
        path.lineTo(pos.dx + cos(nextRootL) * rootR, pos.dy + sin(nextRootL) * rootR);
      }
      path.close();
      canvas.drawPath(path, paint);
      // Rim ring at dedendum circle
      canvas.drawCircle(pos, rootR, paint);
      // Hub
      canvas.drawCircle(pos, 12, paint);
    }
  }
}

class GreekKeyBorderPainter extends ThemeBorderPainter {
  GreekKeyBorderPainter({required super.color, super.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    const inset = 6.0;
    const keyDepth = 5.0;
    const unit = 10.0;
    // (start, end, inDX, inDY) — in direction points into the bubble
    final edges = [
      (Offset(inset, inset), Offset(size.width - inset, inset), 0.0, 1.0),
      (Offset(size.width - inset, inset), Offset(size.width - inset, size.height - inset), -1.0, 0.0),
      (Offset(size.width - inset, size.height - inset), Offset(inset, size.height - inset), 0.0, -1.0),
      (Offset(inset, size.height - inset), Offset(inset, inset), 1.0, 0.0),
    ];

    for (final (start, end, inDX, inDY) in edges) {
      final edgeLen = (start - end).distance;
      final count = (edgeLen / (unit * 2)).floor();
      if (count < 1) continue;
      final adjUnit = edgeLen / count / 2;
      final path = Path();
      double cx = start.dx;
      double cy = start.dy;
      path.moveTo(cx, cy);
      final alongX = (end.dx - start.dx) / edgeLen;
      final alongY = (end.dy - start.dy) / edgeLen;

      for (int i = 0; i < count; i++) {
        cx += alongX * adjUnit;
        cy += alongY * adjUnit;
        path.lineTo(cx, cy);
        cx += inDX * keyDepth;
        cy += inDY * keyDepth;
        path.lineTo(cx, cy);
        cx += alongX * adjUnit;
        cy += alongY * adjUnit;
        path.lineTo(cx, cy);
        cx -= inDX * keyDepth;
        cy -= inDY * keyDepth;
        path.lineTo(cx, cy);
      }
      canvas.drawPath(path, paint);
    }
  }
}

final Map<String, ThemeBorderPainter Function(Color color)> borderPainterFactories = {
  'scalloped': (c) => ScallopedBorderPainter(color: c),
  'dualLine': (c) => DualLineBorderPainter(color: c),
  'grid': (c) => GridBorderPainter(color: c),
  'wavy': (c) => WavyBorderPainter(color: c),
  'shadow': (c) => ShadowBorderPainter(color: c),
  'vine': (c) => VineBorderPainter(color: c),
  'wave': (c) => WaveBorderPainter(color: c),
  'glitch': (c) => GlitchBorderPainter(color: c),
  'floral': (c) => FloralBorderPainter(color: c),
  'gear': (c) => GearBorderPainter(color: c),
  'greekKey': (c) => GreekKeyBorderPainter(color: c),
};
