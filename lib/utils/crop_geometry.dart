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
import 'dart:typed_data';
import 'dart:ui' show Color, Offset, Rect, Size;

import 'package:image/image.dart' as img;

/// Pure math + compositor behind [ImageCropDialog] (the blank-slate crop,
/// 2026-08-14, replacing the crop_your_image dependency).
///
/// The model that makes both Discord-reported crop bugs impossible by
/// construction: THERE IS NO ZOOM. The image is always shown whole
/// (contain-fit), and "capture a larger area" is the crop rect simply being
/// allowed to extend past the image edges — the overhang is filled with
/// [cropFillColor] on save, exactly as previewed. The crop rect lives in
/// SOURCE-pixel space at all times; the widget only maps it to viewport
/// coordinates for painting and gestures, so there is no zoom level to get
/// out of sync with the saved result.

/// Where an image of [imageSize] is painted inside [viewport]: contain-fit,
/// centered. Scales up small images too (standard crop-surface behavior).
Rect containFitRect(Size imageSize, Rect viewport) {
  final scale = math.min(
    viewport.width / imageSize.width,
    viewport.height / imageSize.height,
  );
  final w = imageSize.width * scale;
  final h = imageSize.height * scale;
  return Rect.fromLTWH(
    viewport.left + (viewport.width - w) / 2,
    viewport.top + (viewport.height - h) / 2,
    w,
    h,
  );
}

/// The nine ways a drag can grab the crop rect.
enum CropHandle {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  top,
  bottom,
  left,
  right,
  move,
}

/// Which handle a pointer at [p] grabs on a crop rect painted at [cropVp]
/// (viewport space). Corners win over edges, edges over the interior; a
/// pointer outside everything returns null. [grabRadius] is the tolerance
/// around corners and edge lines.
CropHandle? hitTestCropHandle(Offset p, Rect cropVp, double grabRadius) {
  bool near(Offset corner) => (p - corner).distance <= grabRadius;
  if (near(cropVp.topLeft)) return CropHandle.topLeft;
  if (near(cropVp.topRight)) return CropHandle.topRight;
  if (near(cropVp.bottomLeft)) return CropHandle.bottomLeft;
  if (near(cropVp.bottomRight)) return CropHandle.bottomRight;

  final withinX =
      p.dx >= cropVp.left - grabRadius && p.dx <= cropVp.right + grabRadius;
  final withinY =
      p.dy >= cropVp.top - grabRadius && p.dy <= cropVp.bottom + grabRadius;
  if (withinX && (p.dy - cropVp.top).abs() <= grabRadius) {
    return CropHandle.top;
  }
  if (withinX && (p.dy - cropVp.bottom).abs() <= grabRadius) {
    return CropHandle.bottom;
  }
  if (withinY && (p.dx - cropVp.left).abs() <= grabRadius) {
    return CropHandle.left;
  }
  if (withinY && (p.dx - cropVp.right).abs() <= grabRadius) {
    return CropHandle.right;
  }
  return cropVp.contains(p) ? CropHandle.move : null;
}

/// Apply a source-space [delta] to [rect] for [handle]. The result always
/// stays inside [world] and keeps at least [minSize] on both axes; edges
/// can never cross each other (no inversion).
///
/// [minSize] is capped to the world's dimensions, and an edge whose clamp
/// range comes out inverted (a rect hugging the world edge with the minimum
/// unreachable) FREEZES instead of throwing — with a tiny pixel-art image
/// the world in source pixels can be smaller than the dialog's minimum, and
/// `num.clamp` throws on inverted bounds (found in the 2026-08-14 hostile
/// review; a drag on an 8×8 avatar crashed).
/// With [aspect] set (width / height), corner drags keep that ratio (the
/// opposite corner anchors, the dominant delta axis drives the size) and
/// edge drags freeze — the dialog hides edge handles under a locked aspect.
Rect applyCropDrag(
  Rect rect,
  CropHandle handle,
  Offset delta, {
  required Rect world,
  required double minSize,
  double? aspect,
}) {
  if (handle == CropHandle.move) {
    final dx = delta.dx.clamp(world.left - rect.left, world.right - rect.right);
    final dy = delta.dy.clamp(world.top - rect.top, world.bottom - rect.bottom);
    return rect.shift(Offset(dx, dy));
  }
  if (aspect != null) {
    return _applyAspectCornerDrag(
      rect,
      handle,
      delta,
      world: world,
      minSize: minSize,
      aspect: aspect,
    );
  }

  final movesLeft =
      handle == CropHandle.topLeft ||
      handle == CropHandle.left ||
      handle == CropHandle.bottomLeft;
  final movesRight =
      handle == CropHandle.topRight ||
      handle == CropHandle.right ||
      handle == CropHandle.bottomRight;
  final movesTop =
      handle == CropHandle.topLeft ||
      handle == CropHandle.top ||
      handle == CropHandle.topRight;
  final movesBottom =
      handle == CropHandle.bottomLeft ||
      handle == CropHandle.bottom ||
      handle == CropHandle.bottomRight;

  final min = math.min(minSize, math.min(world.width, world.height));
  double edge(double current, double next, double lo, double hi) =>
      hi < lo ? current : next.clamp(lo, hi);

  var l = rect.left, t = rect.top, r = rect.right, b = rect.bottom;
  if (movesLeft) l = edge(l, l + delta.dx, world.left, r - min);
  if (movesRight) r = edge(r, r + delta.dx, l + min, world.right);
  if (movesTop) t = edge(t, t + delta.dy, world.top, b - min);
  if (movesBottom) b = edge(b, b + delta.dy, t + min, world.bottom);
  return Rect.fromLTRB(l, t, r, b);
}

/// Aspect-locked corner resize: the opposite corner is the fixed anchor, the
/// dominant delta axis drives the new size, and the result is clamped to
/// [world] on both axes and to [minSize] on both axes. Non-corner handles
/// freeze (the dialog hides them under a locked aspect anyway).
Rect _applyAspectCornerDrag(
  Rect rect,
  CropHandle handle,
  Offset delta, {
  required Rect world,
  required double minSize,
  required double aspect,
}) {
  final (Offset anchor, int dirX, int dirY) = switch (handle) {
    CropHandle.topLeft => (rect.bottomRight, -1, -1),
    CropHandle.topRight => (rect.bottomLeft, 1, -1),
    CropHandle.bottomLeft => (rect.topRight, -1, 1),
    CropHandle.bottomRight => (rect.topLeft, 1, 1),
    _ => (Offset.zero, 0, 0),
  };
  if (dirX == 0) return rect;

  // Candidate width from each axis's drag; the axis with the larger motion
  // (normalized into width units, so a wide aspect can't let a tiny
  // vertical wiggle overpower a big horizontal pull) drives the size.
  final wFromX = rect.width + delta.dx * dirX;
  final wFromY = (rect.height + delta.dy * dirY) * aspect;
  var w = delta.dx.abs() >= delta.dy.abs() * aspect ? wFromX : wFromY;

  // Room from the anchor to the world edge, on both axes.
  final roomX = dirX > 0 ? world.right - anchor.dx : anchor.dx - world.left;
  final roomY = dirY > 0 ? world.bottom - anchor.dy : anchor.dy - world.top;
  final wMax = math.min(roomX, roomY * aspect);
  final wMin = math.max(minSize, minSize * aspect);
  if (wMax < wMin) return rect; // no legal aspect rect from this anchor
  w = w.clamp(wMin, wMax);
  final h = w / aspect;

  return Rect.fromLTRB(
    dirX > 0 ? anchor.dx : anchor.dx - w,
    dirY > 0 ? anchor.dy : anchor.dy - h,
    dirX > 0 ? anchor.dx + w : anchor.dx,
    dirY > 0 ? anchor.dy + h : anchor.dy,
  );
}

/// Re-shape [current] to [aspect] (width / height) for a preset switch:
/// keeps the center and roughly the area, clamps into [world] (shrinking to
/// fit, then shifting inside), and respects [minSize] where the world
/// allows it.
Rect aspectFitRect(
  Rect current,
  double aspect, {
  required Rect world,
  required double minSize,
}) {
  var w = math.sqrt(math.max(1e-6, current.width * current.height * aspect));
  var h = w / aspect;
  if (w > world.width) {
    w = world.width;
    h = w / aspect;
  }
  if (h > world.height) {
    h = world.height;
    w = h * aspect;
  }
  final wMin = math.max(minSize, minSize * aspect);
  if (w < wMin && wMin <= world.width && wMin / aspect <= world.height) {
    w = wMin;
    h = w / aspect;
  }
  var r = Rect.fromCenter(center: current.center, width: w, height: h);
  final dx = r.left < world.left
      ? world.left - r.left
      : (r.right > world.right ? world.right - r.right : 0.0);
  final dy = r.top < world.top
      ? world.top - r.top
      : (r.bottom > world.bottom ? world.bottom - r.bottom : 0.0);
  return r.shift(Offset(dx, dy));
}

/// The composited-output background for crop pixels beyond the image bounds
/// — image DATA baked into the saved PNG, not theme chrome (the dialog's own
/// chrome uses AppColors). [CropFill.dark] is the same dark the old Pad
/// Canvas hack filled with, so existing users' padded avatars keep their
/// look; white and transparent were added 2026-08-14 (light artwork was
/// getting a hard dark frame with no say in the matter).
enum CropFill {
  dark(26, 26, 46, 255),
  white(255, 255, 255, 255),
  transparent(0, 0, 0, 0);

  const CropFill(this.r, this.g, this.b, this.a);
  final int r, g, b, a;

  /// The fill as a colour: the user's pick, the same in every app theme.
  Color get color => Color.fromARGB(a, r, g, b);
}

/// Back-compat aliases for the legacy dark fill (tests pin exact pixels).
const int cropFillR = 26, cropFillG = 26, cropFillB = 46;

/// The roaming range for the crop rect around an image of [imageSize]: a
/// full image dimension of padding on every side (so the subject can shrink
/// to 1/9th of the frame), capped so the OUTPUT canvas cannot become a
/// memory bomb — no side of the world exceeds
/// max(image side, [kMaxCropOutputSide]).
const double kMaxCropOutputSide = 8192;

Rect cropWorldRect(Size imageSize) {
  final w = math.min(
    imageSize.width * 3,
    math.max(imageSize.width, kMaxCropOutputSide),
  );
  final h = math.min(
    imageSize.height * 3,
    math.max(imageSize.height, kMaxCropOutputSide),
  );
  return Rect.fromCenter(
    center: Offset(imageSize.width / 2, imageSize.height / 2),
    width: w,
    height: h,
  );
}

/// compute()-friendly crop + composite. [args] is
/// `[Uint8List bytes, int left, int top, int width, int height,
/// int fillR, int fillG, int fillB, int fillA]` — the crop rect in source
/// pixels, which MAY extend beyond the image on any side; the overhang is
/// filled with the given color (alpha 0 = transparent). Output is always
/// RGBA PNG. Throws [FormatException] on undecodable bytes.
Uint8List cropCompositeSync(List<Object> args) {
  final bytes = args[0] as Uint8List;
  final left = args[1] as int;
  final top = args[2] as int;
  final width = args[3] as int;
  final height = args[4] as int;
  final fillR = args[5] as int;
  final fillG = args[6] as int;
  final fillB = args[7] as int;
  final fillA = args[8] as int;
  if (width < 1 || height < 1) {
    throw const FormatException('Crop area is empty');
  }

  // decodeImage returns null for unknown formats but can also throw from a
  // format probe fed truncated garbage (e.g. the PSD prober range-errors on
  // 3 bytes) — normalize both to the documented FormatException.
  img.Image? src;
  try {
    src = img.decodeImage(bytes);
  } catch (_) {
    src = null;
  }
  if (src == null) {
    throw const FormatException('Could not decode the image');
  }

  final out = img.Image(width: width, height: height, numChannels: 4);
  img.fill(out, color: img.ColorRgba8(fillR, fillG, fillB, fillA));

  // Explicit source∩crop intersection — no reliance on the image package
  // clipping negative destination offsets.
  final sx0 = math.max(0, left);
  final sy0 = math.max(0, top);
  final sx1 = math.min(src.width, left + width);
  final sy1 = math.min(src.height, top + height);
  if (sx1 > sx0 && sy1 > sy0) {
    img.compositeImage(
      out,
      src,
      srcX: sx0,
      srcY: sy0,
      srcW: sx1 - sx0,
      srcH: sy1 - sy0,
      dstX: sx0 - left,
      dstY: sy0 - top,
      dstW: sx1 - sx0,
      dstH: sy1 - sy0,
    );
  }
  return img.encodePng(out);
}
