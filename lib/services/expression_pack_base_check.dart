// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// The most pixels a pack's base picture may have (about 40 megapixels).
const int kMaxPackBasePixels = 40 * 1000 * 1000;

/// Why a pack's base picture was refused, in words for the person.
class PackBaseRefusal {
  const PackBaseRefusal(this.message, {this.tooLarge = false});

  final String message;

  /// The picture is over [kMaxPackBasePixels] (the phone answers 413).
  final bool tooLarge;
}

/// What [inspectPackBase] found: the picture's size, or the refusal. A null
/// [refusal] with a null [size] means the bytes are not a picture.
class PackBaseVerdict {
  const PackBaseVerdict.ok(int width, int height)
    : size = (width, height),
      refusal = null;
  const PackBaseVerdict.refused(PackBaseRefusal this.refusal) : size = null;
  const PackBaseVerdict.notPicture() : size = null, refusal = null;

  final (int, int)? size;
  final PackBaseRefusal? refusal;
}

const _formats = 'Please use a PNG picture.';
const _animated = 'That picture is animated. $_formats';

/// The refusal for a picture of [width] x [height], over [kMaxPackBasePixels].
PackBaseRefusal packBaseTooLarge(int width, int height) => PackBaseRefusal(
  'That picture is ${width}x$height, which is too large to build a pack '
  'from. Use one under 40 megapixels.',
  tooLarge: true,
);

PackBaseVerdict _tooLarge(int width, int height) =>
    PackBaseVerdict.refused(packBaseTooLarge(width, height));

PackBaseVerdict _sized(int width, int height) {
  if (width <= 0 || height <= 0) return const PackBaseVerdict.notPicture();
  if (width * height > kMaxPackBasePixels) return _tooLarge(width, height);
  return PackBaseVerdict.ok(width, height);
}

/// Judges [raw] before it reaches an image decoder, from its bytes alone:
/// only a PNG is taken (anything else, JPEG and WebP included, is refused);
/// an animated PNG is refused; the size is read here (never from the decoder,
/// which allocates what a header declares before anything is compared); and
/// the compressed data is checked to inflate to no more than its size can
/// hold, stopping the moment it does. A small file can declare or inflate to
/// gigabytes, so nothing large is allocated here.
PackBaseVerdict inspectPackBase(Uint8List raw) {
  if (!_isPng(raw)) {
    return const PackBaseVerdict.refused(PackBaseRefusal(_formats));
  }
  try {
    return _png(raw);
  } on RangeError {
    return const PackBaseVerdict.notPicture(); // cut short
  }
}

String _fourcc(Uint8List b, int at) => String.fromCharCodes(b, at, at + 4);
int _u32be(Uint8List b, int at) =>
    (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];

// ── PNG ─────────────────────────────────────────────────────────────────────

bool _isPng(Uint8List b) =>
    b.length > 8 &&
    b[0] == 137 &&
    b[1] == 80 &&
    b[2] == 78 &&
    b[3] == 71 &&
    b[4] == 13 &&
    b[5] == 10 &&
    b[6] == 26 &&
    b[7] == 10;

const _channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4};
const _depths = {
  0: [1, 2, 4, 8, 16],
  2: [8, 16],
  3: [1, 2, 4, 8],
  4: [8, 16],
  6: [8, 16],
};

PackBaseVerdict _png(Uint8List b) {
  var at = 8;
  int? width, height, bits, interlace;
  final idat = <(int, int)>[];
  var ended = false;
  while (at + 12 <= b.length) {
    final length = _u32be(b, at);
    final type = _fourcc(b, at + 4);
    final data = at + 8;
    if (length > b.length - data - 4) break;
    if (width == null) {
      if (type != 'IHDR' || length != 13) {
        return const PackBaseVerdict.notPicture();
      }
      width = _u32be(b, data);
      height = _u32be(b, data + 4);
      final depth = b[data + 8];
      final color = b[data + 9];
      interlace = b[data + 12];
      if (!(_depths[color]?.contains(depth) ?? false) ||
          b[data + 10] != 0 ||
          b[data + 11] != 0 ||
          interlace > 1) {
        return const PackBaseVerdict.notPicture();
      }
      bits = _channels[color]! * depth;
      final sized = _sized(width, height);
      if (sized.size == null) return sized;
    } else if (type == 'IHDR') {
      // The decoder takes the size, depth and colour type from the last IHDR.
      return const PackBaseVerdict.notPicture();
    } else if (type == 'acTL' || type == 'fcTL' || type == 'fdAT') {
      return const PackBaseVerdict.refused(PackBaseRefusal(_animated));
    } else if (type == 'IDAT') {
      idat.add((data, length));
    } else if (type == 'IEND') {
      ended = true;
      break;
    }
    at = data + length + 4;
  }
  if (width == null || !ended || idat.isEmpty) {
    return const PackBaseVerdict.notPicture();
  }
  final most = _pngDataSize(width, height!, bits!, interlace == 1) + 1024;
  return _inflatesWithin(b, idat, most)
      ? PackBaseVerdict.ok(width, height)
      : const PackBaseVerdict.notPicture();
}

/// How many bytes the filtered scanlines of a [width] x [height] picture take.
int _pngDataSize(int width, int height, int bits, bool interlaced) {
  int pass(int w, int h) =>
      (w <= 0 || h <= 0) ? 0 : h * (1 + (w * bits + 7) ~/ 8);
  if (!interlaced) return pass(width, height);
  const adam7 = [
    (0, 0, 8, 8),
    (4, 0, 8, 8),
    (0, 4, 4, 8),
    (2, 0, 4, 4),
    (0, 2, 2, 4),
    (1, 0, 2, 2),
    (0, 1, 1, 2),
  ];
  var total = 0;
  for (final (x0, y0, dx, dy) in adam7) {
    total += pass((width - x0 + dx - 1) ~/ dx, (height - y0 + dy - 1) ~/ dy);
  }
  return total;
}

/// Streams the PNG's compressed data through zlib and stops as soon as more
/// than [cap] bytes have come out. Nothing is kept.
bool _inflatesWithin(Uint8List b, List<(int, int)> idat, int cap) {
  final sink = _CountingSink(cap);
  final input = ZLibDecoder().startChunkedConversion(sink);
  try {
    for (final (at, length) in idat) {
      input.add(Uint8List.sublistView(b, at, at + length));
    }
    input.close();
  } on _OverCap {
    return false;
  } on FormatException {
    return false;
  } on Exception {
    return false;
  }
  return true;
}

class _OverCap implements Exception {
  const _OverCap();
}

class _CountingSink extends ByteConversionSinkBase {
  _CountingSink(this.cap);

  final int cap;
  int _total = 0;

  @override
  void add(List<int> chunk) {
    _total += chunk.length;
    if (_total > cap) throw const _OverCap();
  }

  @override
  void close() {}
}
