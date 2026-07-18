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

import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Idefics3/SmolVLM image preprocessing, ported from the reference HF
/// `Idefics3ImageProcessor` with `size.longest_edge = 1024` and
/// `max_image_size.longest_edge = 512`:
///
///  1. Rescale so the longest edge is exactly 1024 (up- OR down-scaling),
///     the short edge keeps aspect and is rounded UP to even.
///  2. Round each dimension UP to a multiple of 512 (this deliberately
///     distorts aspect slightly — the reference does the same).
///  3. Split the canvas into row-major 512×512 tiles (always exact — no tile
///     padding is ever needed after step 2).
///  4. Append a "global" frame: the canvas rescaled to longest edge 512
///     (even-rounded short edge), padded bottom/right with zeros to 512×512;
///     only this frame can carry padding, tracked in [pixelMask].
///  5. Normalize to (x/255 − 0.5)/0.5; padding stays 0.0 in normalized space
///     (the reference pads after normalization).
///
/// Sizes/grids match the reference exactly (they drive the prompt layout);
/// pixel values differ microscopically because the reference resamples twice
/// with LANCZOS while this port resizes once with cubic — irrelevant to
/// caption quality and much cheaper.
class SmolVlmFrames {
  /// NCHW frames: [frameCount, 3, 512, 512] — tiles row-major, then global.
  final Float32List pixelValues;

  /// Per-pixel validity: [frameCount, 512, 512] — false only on the global
  /// frame's padding.
  final List<bool> pixelMask;

  final int rows;
  final int cols;

  SmolVlmFrames({
    required this.pixelValues,
    required this.pixelMask,
    required this.rows,
    required this.cols,
  });

  int get frameCount => rows * cols + 1;
}

const int _kFrameSide = 512;
const int _kLongestEdge = 1024;

/// Longest edge → [maxLen], short edge keeps aspect, rounded UP to even
/// (mirrors `_resize_output_size_rescale_to_max_len`).
(int, int) _rescaleToMaxLen(int width, int height, int maxLen) {
  final aspect = width / height;
  int w, h;
  if (width >= height) {
    w = maxLen;
    h = (w / aspect).toInt();
    if (h.isOdd) h += 1;
  } else {
    h = maxLen;
    w = (h * aspect).toInt();
    if (w.isOdd) w += 1;
  }
  return (w < 1 ? 1 : w, h < 1 ? 1 : h);
}

/// Each dimension rounded UP to a multiple of 512, aspect recomputed from the
/// step-1 size (mirrors `resize_for_vision_encoder`).
(int, int) _ceilToFrameMultiples(int width, int height) {
  final aspect = width / height;
  int w, h;
  if (width >= height) {
    w = ((width + _kFrameSide - 1) ~/ _kFrameSide) * _kFrameSide;
    h = (w / aspect).toInt();
    h = ((h + _kFrameSide - 1) ~/ _kFrameSide) * _kFrameSide;
  } else {
    h = ((height + _kFrameSide - 1) ~/ _kFrameSide) * _kFrameSide;
    w = (h * aspect).toInt();
    w = ((w + _kFrameSide - 1) ~/ _kFrameSide) * _kFrameSide;
  }
  return (w, h);
}

/// Write [source] into [dest]'s frame [frameIndex] as normalized NCHW floats.
/// [validWidth]/[validHeight] bound the real pixels (rest stays 0.0 padding).
void _writeFrame(
  Float32List dest,
  int frameIndex,
  img.Image source,
  int validWidth,
  int validHeight,
) {
  final planeSize = _kFrameSide * _kFrameSide;
  final base = frameIndex * 3 * planeSize;
  for (var y = 0; y < validHeight; y++) {
    for (var x = 0; x < validWidth; x++) {
      final p = source.getPixel(x, y);
      final idx = y * _kFrameSide + x;
      // rNormalized/gNormalized/bNormalized are 0..1 REGARDLESS of the source
      // bit depth. Reading the raw p.r (0..255 for uint8 but 0..65535 for a
      // uint16 PNG — which package:image preserves through decode/resize/encode)
      // would feed the vision encoder values in the hundreds and produce a
      // garbage caption. Map the normalized channel to the model's [-1, 1].
      dest[base + idx] = p.rNormalized * 2 - 1;
      dest[base + planeSize + idx] = p.gNormalized * 2 - 1;
      dest[base + 2 * planeSize + idx] = p.bNormalized * 2 - 1;
    }
  }
}

/// Decode + preprocess in one step — shaped for `compute()` so the ~1M-pixel
/// resample never runs on the UI isolate. Null when [bytes] isn't an image.
SmolVlmFrames? decodeAndPreprocessForSmolVlm(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  return preprocessForSmolVlm(decoded);
}

/// Run the full preprocessing over a decoded RGB image.
SmolVlmFrames preprocessForSmolVlm(img.Image source) {
  final (w1, h1) = _rescaleToMaxLen(source.width, source.height, _kLongestEdge);
  final (w2, h2) = _ceilToFrameMultiples(w1, h1);
  // Linear, not cubic: pure-Dart resampling is a real chunk of caption
  // latency and the VLM can't tell the difference (the reference's LANCZOS
  // is a third resampler again — sizes/grids are the part that must match).
  final canvas = img.copyResize(
    source,
    width: w2,
    height: h2,
    interpolation: img.Interpolation.linear,
  );
  final cols = w2 ~/ _kFrameSide;
  final rows = h2 ~/ _kFrameSide;
  final frameCount = rows * cols + 1;
  final planeSize = _kFrameSide * _kFrameSide;
  final pixels = Float32List(frameCount * 3 * planeSize);
  final mask = List<bool>.filled(frameCount * planeSize, true);

  var frame = 0;
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      final tile = img.copyCrop(
        canvas,
        x: c * _kFrameSide,
        y: r * _kFrameSide,
        width: _kFrameSide,
        height: _kFrameSide,
      );
      _writeFrame(pixels, frame, tile, _kFrameSide, _kFrameSide);
      frame++;
    }
  }

  // Global frame: whole canvas at longest edge 512, zero-padded to 512×512.
  final (wg, hg) = _rescaleToMaxLen(w2, h2, _kFrameSide);
  final global = img.copyResize(
    canvas,
    width: wg,
    height: hg,
    interpolation: img.Interpolation.linear,
  );
  _writeFrame(pixels, frame, global, wg, hg);
  final maskBase = frame * planeSize;
  for (var y = 0; y < _kFrameSide; y++) {
    for (var x = 0; x < _kFrameSide; x++) {
      if (y >= hg || x >= wg) mask[maskBase + y * _kFrameSide + x] = false;
    }
  }

  return SmolVlmFrames(
    pixelValues: pixels,
    pixelMask: mask,
    rows: rows,
    cols: cols,
  );
}
