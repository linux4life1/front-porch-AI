// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Twitter/X verified silhouette `d` — byte-identical to hub
/// `backporch-server/site/src/stoop/ui.js` `TWITTER_BADGE` (viewBox 0 0 22 22).
const String kStoopCheckPath =
    'M20.396 11c-.018-.646-.215-1.275-.57-1.816-.354-.54-.852-.972-1.438-1.246.223-.607.27-1.264.14-1.897-.131-.634-.437-1.218-.882-1.687-.47-.445-1.053-.75-1.687-.882-.633-.13-1.29-.083-1.897.14-.273-.587-.704-1.086-1.245-1.44S11.647 1.62 11 1.604c-.646.017-1.273.213-1.813.568s-.969.854-1.24 1.44c-.608-.223-1.267-.272-1.902-.14-.635.13-1.22.436-1.69.882-.445.47-.749 1.055-.878 1.688-.13.633-.08 1.29.144 1.896-.587.274-1.087.705-1.443 1.245-.356.54-.555 1.17-.574 1.817.02.647.218 1.276.574 1.817.356.54.856.972 1.443 1.245-.224.606-.274 1.263-.144 1.896.13.634.433 1.218.877 1.688.47.443 1.054.747 1.687.878.633.132 1.29.084 1.897-.136.274.586.705 1.084 1.246 1.439.54.354 1.17.551 1.816.569.647-.016 1.276-.213 1.817-.567s.972-.854 1.245-1.44c.604.239 1.266.296 1.903.164.636-.132 1.22-.447 1.68-.907.46-.46.776-1.044.908-1.681s.075-1.299-.165-1.903c.586-.274 1.084-.705 1.439-1.246.354-.54.551-1.17.569-1.816zM9.662 14.85l-3.429-3.428 1.293-1.302 2.072 2.072 4.4-4.794 1.347 1.246z';

/// Hub viewBox edge. Scale the parsed path by `size / kStoopCheckViewBox`.
const double kStoopCheckViewBox = 22;

final Path kStoopCheckParsedPath = parseSvgPath(kStoopCheckPath);

/// Gold owner / blue trusted-uploader check. Renders nothing if [verification]
/// is missing or unknown. Sit this in a Wrap/Row next to the handle — do not
/// bake the name in. Hub alignment: slightly below cap-height
/// (`.hub-check { vertical-align: -0.18em }`).
class StoopVerifiedBadge extends StatelessWidget {
  final String? verification;
  final double size;
  const StoopVerifiedBadge({
    super.key,
    required this.verification,
    this.size = 16,
  });

  @override
  Widget build(BuildContext context) {
    final v = verification;
    if (v != 'gold' && v != 'blue') return const SizedBox.shrink();
    final color = v == 'gold'
        ? AppColors.stoopCheckGold
        : AppColors.stoopCheckBlue;
    final label = v == 'gold' ? 'Gold verified' : 'Verified';
    final tooltip = v == 'gold' ? 'Stoop owner' : 'Trusted creator';
    // Hub: width 1.15em, margin-left 0.22em, vertical-align -0.18em.
    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: label,
        image: true,
        excludeSemantics: true,
        child: Padding(
          padding: EdgeInsets.only(left: size * 0.1913),
          child: Baseline(
            baseline: size * 0.8435,
            baselineType: TextBaseline.alphabetic,
            child: SizedBox(
              width: size,
              height: size,
              child: CustomPaint(painter: _StoopCheckPainter(color)),
            ),
          ),
        ),
      ),
    );
  }
}

class _StoopCheckPainter extends CustomPainter {
  final Color color;
  const _StoopCheckPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / kStoopCheckViewBox;
    final sy = size.height / kStoopCheckViewBox;
    canvas.save();
    canvas.scale(sx, sy);
    canvas.drawPath(
      kStoopCheckParsedPath,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StoopCheckPainter old) => old.color != color;
}

/// SVG path subset used by the hub silhouette: M/m L/l C/c S/s Z/z, plus
/// implicit repeats and sign/dot number separators.
Path parseSvgPath(String d) {
  final path = Path();
  final n = d.length;
  var i = 0;
  var px = 0.0, py = 0.0;
  var sx = 0.0, sy = 0.0;
  var c2x = 0.0, c2y = 0.0;
  var lastCubic = false;
  var cmd = '';
  var implicitLine = false;

  bool isDigit(int c) => c >= 0x30 && c <= 0x39;
  bool isCmd(int c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

  void skipSep() {
    while (i < n) {
      final c = d.codeUnitAt(i);
      if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x2C) {
        i++;
      } else {
        break;
      }
    }
  }

  bool hasNum() {
    skipSep();
    if (i >= n) return false;
    final c = d.codeUnitAt(i);
    return c == 0x2B || c == 0x2D || c == 0x2E || isDigit(c);
  }

  double readNum() {
    skipSep();
    final start = i;
    if (i < n) {
      final c = d.codeUnitAt(i);
      if (c == 0x2B || c == 0x2D) i++;
    }
    while (i < n && isDigit(d.codeUnitAt(i))) {
      i++;
    }
    if (i < n && d.codeUnitAt(i) == 0x2E) {
      i++;
      while (i < n && isDigit(d.codeUnitAt(i))) {
        i++;
      }
    }
    if (i < n) {
      final e = d.codeUnitAt(i);
      if (e == 0x65 || e == 0x45) {
        i++;
        if (i < n) {
          final s = d.codeUnitAt(i);
          if (s == 0x2B || s == 0x2D) i++;
        }
        while (i < n && isDigit(d.codeUnitAt(i))) {
          i++;
        }
      }
    }
    return double.parse(d.substring(start, i));
  }

  void markNotCubic() => lastCubic = false;

  while (i < n) {
    skipSep();
    if (i >= n) break;
    if (isCmd(d.codeUnitAt(i))) {
      cmd = d[i];
      i++;
      implicitLine = cmd == 'M' || cmd == 'm';
    } else if (!hasNum()) {
      i++;
      continue;
    }

    switch (cmd) {
      case 'M':
      case 'm':
        if (!hasNum()) break;
        final rel = cmd == 'm';
        final x = readNum();
        final y = readNum();
        if (implicitLine) {
          px = rel ? px + x : x;
          py = rel ? py + y : y;
          sx = px;
          sy = py;
          path.moveTo(px, py);
          markNotCubic();
          implicitLine = false;
          cmd = rel ? 'l' : 'L';
        } else {
          // Subsequent M pairs are lines (SVG spec).
          px = rel ? px + x : x;
          py = rel ? py + y : y;
          path.lineTo(px, py);
          markNotCubic();
        }
      case 'L':
      case 'l':
        if (!hasNum()) break;
        final rel = cmd == 'l';
        px = rel ? px + readNum() : readNum();
        py = rel ? py + readNum() : readNum();
        path.lineTo(px, py);
        markNotCubic();
      case 'C':
      case 'c':
        if (!hasNum()) break;
        final rel = cmd == 'c';
        final x1 = rel ? px + readNum() : readNum();
        final y1 = rel ? py + readNum() : readNum();
        final x2 = rel ? px + readNum() : readNum();
        final y2 = rel ? py + readNum() : readNum();
        final x = rel ? px + readNum() : readNum();
        final y = rel ? py + readNum() : readNum();
        path.cubicTo(x1, y1, x2, y2, x, y);
        c2x = x2;
        c2y = y2;
        px = x;
        py = y;
        lastCubic = true;
      case 'S':
      case 's':
        if (!hasNum()) break;
        final rel = cmd == 's';
        final x1 = lastCubic ? 2 * px - c2x : px;
        final y1 = lastCubic ? 2 * py - c2y : py;
        final x2 = rel ? px + readNum() : readNum();
        final y2 = rel ? py + readNum() : readNum();
        final x = rel ? px + readNum() : readNum();
        final y = rel ? py + readNum() : readNum();
        path.cubicTo(x1, y1, x2, y2, x, y);
        c2x = x2;
        c2y = y2;
        px = x;
        py = y;
        lastCubic = true;
      case 'Z':
      case 'z':
        path.close();
        px = sx;
        py = sy;
        markNotCubic();
      default:
        // Skip an unknown command's numbers so a future letter can recover.
        while (hasNum()) {
          readNum();
        }
    }
  }
  return path;
}
