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

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final rng = Random(42);
    for (int side = 0; side < 4; side++) {
      final path = Path();
      double x, y;
      if (side == 0) { x = 8; y = rng.nextDouble() * size.height; }
      else if (side == 1) { x = size.width - 8; y = rng.nextDouble() * size.height; }
      else if (side == 2) { x = rng.nextDouble() * size.width; y = 8; }
      else { x = rng.nextDouble() * size.width; y = size.height - 8; }
      path.moveTo(x, y);
      for (int i = 0; i < 4; i++) {
        final dx = rng.nextDouble() * 20 - 10;
        final dy = rng.nextDouble() * 20 - 10;
        path.relativeQuadraticBezierTo(dx, dy, rng.nextDouble() * 16 - 8, rng.nextDouble() * 16 - 8);
      }
      canvas.drawPath(path, paint);
      final dotPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), 2.5, dotPaint);
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
    final centers = [
      Offset(12, 12),
      Offset(size.width - 12, 12),
      Offset(size.width / 2, size.height - 12),
    ];
    for (final center in centers) {
      final path = Path();
      const teeth = 8;
      final outerR = 8.0;
      final innerR = 5.0;
      for (int i = 0; i < teeth; i++) {
        final a1 = i * 2 * pi / teeth;
        final a2 = a1 + pi / teeth;
        if (i == 0) {
          path.moveTo(center.dx + cos(a1) * outerR, center.dy + sin(a1) * outerR);
        } else {
          path.lineTo(center.dx + cos(a1) * outerR, center.dy + sin(a1) * outerR);
        }
        path.lineTo(center.dx + cos(a2) * innerR, center.dy + sin(a2) * innerR);
      }
      path.close();
      canvas.drawPath(path, paint);
      canvas.drawCircle(center, 2, paint..style = PaintingStyle.fill);
      paint.style = PaintingStyle.stroke;
    }
    final border = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRect(Offset.zero & size, border);
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
};
