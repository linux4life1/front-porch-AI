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

const _formats = 'Use a PNG, JPEG or still WebP picture.';
const _animated = 'That picture is animated. $_formats';

PackBaseVerdict _tooLarge(int width, int height) => PackBaseVerdict.refused(
  PackBaseRefusal(
    'That picture is ${width}x$height, which is too large to build a pack '
    'from. Use one under 40 megapixels.',
    tooLarge: true,
  ),
);

PackBaseVerdict _sized(int width, int height) {
  if (width <= 0 || height <= 0) return const PackBaseVerdict.notPicture();
  if (width * height > kMaxPackBasePixels) return _tooLarge(width, height);
  return PackBaseVerdict.ok(width, height);
}

/// Judges [raw] before it reaches an image decoder, from its bytes alone:
/// only PNG, JPEG and still WebP are taken; animated pictures (APNG,
/// animated WebP) are refused; the size is read here (never from the decoder,
/// which allocates what a header declares before anything is compared); and a
/// PNG's compressed data is checked to inflate to no more than its size can
/// hold, stopping the moment it does. A small file can declare or inflate to
/// gigabytes, so nothing large is allocated here.
PackBaseVerdict inspectPackBase(Uint8List raw) {
  try {
    if (_isPng(raw)) return _png(raw);
    if (raw.length > 3 && raw[0] == 0xFF && raw[1] == 0xD8 && raw[2] == 0xFF) {
      return _jpeg(raw);
    }
    if (raw.length > 12 &&
        _fourcc(raw, 0) == 'RIFF' &&
        _fourcc(raw, 8) == 'WEBP') {
      return _webp(raw);
    }
  } on RangeError {
    return const PackBaseVerdict.notPicture(); // cut short
  }
  if (raw.length > 4) {
    return const PackBaseVerdict.refused(PackBaseRefusal(_formats));
  }
  return const PackBaseVerdict.notPicture();
}

String _fourcc(Uint8List b, int at) => String.fromCharCodes(b, at, at + 4);
int _u32be(Uint8List b, int at) =>
    (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];
int _u16be(Uint8List b, int at) => (b[at] << 8) | b[at + 1];
int _u16le(Uint8List b, int at) => b[at] | (b[at + 1] << 8);
int _u24le(Uint8List b, int at) => b[at] | (b[at + 1] << 8) | (b[at + 2] << 16);
int _u32le(Uint8List b, int at) =>
    b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24);

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

// ── JPEG ────────────────────────────────────────────────────────────────────

PackBaseVerdict _jpeg(Uint8List b) {
  var at = 2;
  while (at + 4 <= b.length) {
    if (b[at] != 0xFF) return const PackBaseVerdict.notPicture();
    var marker = b[at + 1];
    while (marker == 0xFF && at + 2 < b.length) {
      at++; // fill bytes before a marker
      marker = b[at + 1];
    }
    if (marker == 0xD9 || marker == 0xDA) {
      return const PackBaseVerdict.notPicture(); // no frame header first
    }
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD8)) {
      at += 2; // no length
      continue;
    }
    final length = _u16be(b, at + 2);
    if (length < 2) return const PackBaseVerdict.notPicture();
    // Baseline, extended sequential and progressive: what the decoders take.
    if (marker == 0xC0 || marker == 0xC1 || marker == 0xC2) {
      if (length < 8) return const PackBaseVerdict.notPicture();
      return _sized(_u16be(b, at + 7), _u16be(b, at + 5));
    }
    if (marker >= 0xC3 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC) {
      return const PackBaseVerdict.refused(PackBaseRefusal(_formats));
    }
    at += 2 + length;
  }
  return const PackBaseVerdict.notPicture();
}

// ── WebP ────────────────────────────────────────────────────────────────────

PackBaseVerdict _webp(Uint8List b) {
  final end = (8 + _u32le(b, 4)).clamp(12, b.length);
  var at = 12;
  (int, int)? canvas;
  (int, int)? still;
  while (at + 8 <= end) {
    final type = _fourcc(b, at);
    final size = _u32le(b, at + 4);
    final data = at + 8;
    if (size > end - data) break;
    switch (type) {
      case 'VP8X':
        if (size < 10) return const PackBaseVerdict.notPicture();
        if (b[data] & 0x02 != 0) {
          return const PackBaseVerdict.refused(PackBaseRefusal(_animated));
        }
        canvas = (1 + _u24le(b, data + 4), 1 + _u24le(b, data + 7));
        final sized = _sized(canvas.$1, canvas.$2);
        if (sized.size == null) return sized;
      case 'ANIM' || 'ANMF':
        return const PackBaseVerdict.refused(PackBaseRefusal(_animated));
      case 'VP8 ':
        if (size < 10 ||
            b[data + 3] != 0x9D ||
            b[data + 4] != 0x01 ||
            b[data + 5] != 0x2A) {
          return const PackBaseVerdict.notPicture();
        }
        still ??= (_u16le(b, data + 6) & 0x3FFF, _u16le(b, data + 8) & 0x3FFF);
      case 'VP8L':
        if (size < 5 || b[data] != 0x2F) {
          return const PackBaseVerdict.notPicture();
        }
        final bits = _u32le(b, data + 1);
        still ??= ((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1);
    }
    if (still != null) {
      final sized = _sized(still.$1, still.$2);
      if (sized.size == null) return sized;
    }
    at = data + size + (size & 1);
  }
  if (still == null) return const PackBaseVerdict.notPicture();
  if (canvas != null && canvas != still) {
    // The canvas and the picture inside it must agree: a decoder allocates one
    // and fills the other.
    return const PackBaseVerdict.notPicture();
  }
  return PackBaseVerdict.ok(still.$1, still.$2);
}
