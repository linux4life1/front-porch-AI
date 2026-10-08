// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'expression_pack_base_check.dart';

/// A refusal raised while checking a picture before it is converted.
class PackPictureRefused implements Exception {
  const PackPictureRefused(this.refusal);

  final PackBaseRefusal refusal;
}

const _notPicture = PackBaseRefusal(
  'That file could not be read as a picture. Please use a PNG picture.',
);
const _jpegKind = PackBaseRefusal(
  'That kind of JPEG is not supported. Please use a PNG picture.',
);

/// A JPEG that passed [checkJpeg]: [bytes] is what the decoder is given.
class CheckedJpeg {
  const CheckedJpeg(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final int width;
  final int height;
}

int _u16(Uint8List b, int at) => (b[at] << 8) | b[at + 1];

/// Reads [raw] as a JPEG the way the decoder walks it, but strictly, and
/// returns a copy holding only what a decode needs.
///
/// The decoder allocates for the frame header the moment it reads one, before
/// any pixel is decoded, and it walks in a tolerant way: it skips stray bytes
/// between segments, and after an unknown segment it can step back and read a
/// frame header out of that segment's own last bytes. So this walk takes no
/// such liberty: every segment sits right after the last, only the common
/// markers are known, exactly one frame header comes before the first scan,
/// and nothing but the tables and further scans of a progressive file follow
/// it. What is left is a file both readings agree on, so the size found here
/// is the size the decoder allocates. EXIF, ICC, comments and other
/// application segments are dropped (the Adobe one, which says how the colours
/// are stored, is kept): the decoder does not use them for the pixels.
///
/// Throws [PackPictureRefused] for a file that is not taken.
CheckedJpeg checkJpeg(Uint8List b) {
  try {
    return _check(b);
  } on RangeError {
    throw const PackPictureRefused(_notPicture); // cut short
  }
}

CheckedJpeg _check(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) {
    throw const PackPictureRefused(_notPicture);
  }
  final head = BytesBuilder(copy: false)..add(const [0xFF, 0xD8]);
  var width = 0, height = 0;
  var frame = false;
  int? firstScan;
  var at = 2;
  while (true) {
    if (b[at] != 0xFF) throw const PackPictureRefused(_notPicture);
    while (b[at + 1] == 0xFF) {
      at++; // fill bytes before a marker
    }
    final marker = b[at + 1];
    if (marker == 0xD9) {
      if (!frame || firstScan == null) {
        throw const PackPictureRefused(_notPicture);
      }
      head.add(Uint8List.sublistView(b, firstScan, at + 2));
      return CheckedJpeg(head.takeBytes(), width, height);
    }
    final isApp = (marker >= 0xE0 && marker <= 0xEF) || marker == 0xFE;
    final isTable = marker == 0xDB || marker == 0xC4 || marker == 0xDD;
    final isFrame = marker >= 0xC0 && marker <= 0xC2;
    if (!isApp && !isTable && !isFrame && marker != 0xDA) {
      throw PackPictureRefused(
        (marker >= 0xC3 && marker <= 0xCF) ? _jpegKind : _notPicture,
      );
    }
    final length = _u16(b, at + 2);
    final end = at + 2 + length;
    if (length < 2 || end > b.length) {
      throw const PackPictureRefused(_notPicture);
    }
    if (isApp) {
      if (firstScan != null) throw const PackPictureRefused(_notPicture);
      if (marker == 0xEE) head.add(Uint8List.sublistView(b, at, end));
    } else if (isTable) {
      if (firstScan == null) head.add(Uint8List.sublistView(b, at, end));
    } else if (isFrame) {
      if (frame) throw const PackPictureRefused(_notPicture);
      (width, height) = _frameSize(b, at, length);
      frame = true;
      head.add(Uint8List.sublistView(b, at, end));
    } else {
      if (!frame) throw const PackPictureRefused(_notPicture);
      firstScan ??= at;
      at = _endOfScan(b, end);
      continue;
    }
    at = end;
  }
}

/// The size in a frame header at [at], after checking what the decoder would
/// allocate for: 8-bit samples, one or three components, sampling factors of
/// at most 4, and a size that is worth converting.
(int, int) _frameSize(Uint8List b, int at, int length) {
  final components = b[at + 9];
  if (b[at + 4] != 8 ||
      (components != 1 && components != 3) ||
      length != 8 + 3 * components) {
    throw const PackPictureRefused(_jpegKind);
  }
  for (var i = 0; i < components; i++) {
    final sampling = b[at + 11 + 3 * i];
    final h = sampling >> 4, v = sampling & 15;
    if (h < 1 || h > 4 || v < 1 || v > 4 || b[at + 12 + 3 * i] > 3) {
      throw const PackPictureRefused(_jpegKind);
    }
  }
  final height = _u16(b, at + 5), width = _u16(b, at + 7);
  if (width == 0 || height == 0) throw const PackPictureRefused(_notPicture);
  if (width * height > kMaxPackBasePixels) {
    throw PackPictureRefused(packBaseTooLarge(width, height));
  }
  return (width, height);
}

/// Where the marker after a scan begins: the entropy-coded data holds no
/// marker but stuffed zeros and the eight restart markers.
int _endOfScan(Uint8List b, int from) {
  for (var i = from; i + 1 < b.length; i++) {
    if (b[i] != 0xFF) continue;
    var j = i + 1;
    while (j < b.length && b[j] == 0xFF) {
      j++;
    }
    if (j >= b.length) break;
    final next = b[j];
    if (next == 0 || (next >= 0xD0 && next <= 0xD7)) {
      i = j;
      continue;
    }
    return j - 1;
  }
  throw const PackPictureRefused(_notPicture);
}
