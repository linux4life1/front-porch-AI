// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Small files built to be hostile to an image decoder: each is a few bytes or
// kilobytes on disk and declares or inflates to something enormous.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'huge_png.dart';

const List<int> _pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];

Uint8List _u32(int v) => (ByteData(4)..setUint32(0, v)).buffer.asUint8List();
Uint8List _u32le(int v) =>
    (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List();

/// One PNG chunk: length, type, data, CRC.
List<int> pngChunk(String type, List<int> data) {
  final body = [...type.codeUnits, ...data];
  return [..._u32(data.length), ...body, ..._u32(pngCrc32(body))];
}

List<int> pngHeader(
  int width,
  int height, {
  int depth = 8,
  int color = 6,
  int interlace = 0,
}) => pngChunk('IHDR', [
  ..._u32(width),
  ..._u32(height),
  depth,
  color,
  0,
  0,
  interlace,
]);

/// The zlib stream of [size] zero bytes, made without holding them.
Uint8List zeroZlib(int size) {
  final out = BytesBuilder(copy: false);
  final sink = ZLibEncoder(
    level: 9,
  ).startChunkedConversion(ByteConversionSinkAdapter(out));
  final block = Uint8List(1 << 20);
  var left = size;
  while (left > 0) {
    final n = left < block.length ? left : block.length;
    sink.add(n == block.length ? block : Uint8List(n));
    left -= n;
  }
  sink.close();
  return out.toBytes();
}

class ByteConversionSinkAdapter extends ByteConversionSinkBase {
  ByteConversionSinkAdapter(this.out);

  final BytesBuilder out;

  @override
  void add(List<int> chunk) => out.add(chunk);

  @override
  void close() {}
}

/// A PNG that says it is [width] x [height] and whose data inflates to
/// [inflated] bytes, however small the file is.
Uint8List pngBomb({int width = 64, int height = 64, required int inflated}) =>
    Uint8List.fromList([
      ..._pngSignature,
      ...pngHeader(width, height),
      ...pngChunk('IDAT', zeroZlib(inflated)),
      ...pngChunk('IEND', const []),
    ]);

/// An honest [width] x [height] 8-bit RGBA PNG with [extra] more bytes of
/// scanline data than that size holds.
Uint8List pngWithExtra(int width, int height, {int extra = 0}) => pngBomb(
  width: width,
  height: height,
  inflated: height * (1 + width * 4) + extra,
);

/// A PNG made animated: an acTL chunk (and frame chunks) after the header, the
/// picture a small honest one, the first frame [frameWidth] x [frameHeight].
Uint8List apng({
  int frames = 1,
  int frameWidth = 4,
  int frameHeight = 4,
  int width = 4,
  int height = 4,
}) {
  final out = <int>[
    ..._pngSignature,
    ...pngHeader(width, height),
    ...pngChunk('acTL', [..._u32(frames), ..._u32(0)]),
  ];
  for (var i = 0; i < frames; i++) {
    out.addAll(
      pngChunk('fcTL', [
        ..._u32(i * 2),
        ..._u32(frameWidth),
        ..._u32(frameHeight),
        ..._u32(0),
        ..._u32(0),
        0,
        0,
        0,
        0,
        1,
        0,
        0,
      ]),
    );
  }
  out
    ..addAll(pngChunk('IDAT', zeroZlib(height * (1 + width * 4))))
    ..addAll(pngChunk('IEND', const []));
  return Uint8List.fromList(out);
}

/// A JPEG that is nothing but markers: SOI, an APP0 segment, a frame header
/// declaring [width] x [height], EOI.
Uint8List tinyJpeg(int width, int height, {int sof = 0xC0}) =>
    Uint8List.fromList([
      0xFF, 0xD8, //
      0xFF, 0xE0, 0x00, 0x08, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x00, //
      0xFF, sof, 0x00, 0x11, 0x08, height >> 8, height & 0xFF, width >> 8,
      width & 0xFF, 0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01,
      0xFF, 0xD9,
    ]);

List<int> _riffChunk(String type, List<int> data) => [
  ...type.codeUnits,
  ..._u32le(data.length),
  ...data,
  if (data.length.isOdd) 0,
];

Uint8List _riff(List<int> chunks) => Uint8List.fromList([
  ...'RIFF'.codeUnits,
  ..._u32le(4 + chunks.length),
  ...'WEBP'.codeUnits,
  ...chunks,
]);

List<int> vp8l(int width, int height) => _riffChunk('VP8L', [
  0x2F,
  ..._u32le((width - 1) | ((height - 1) << 14)),
  0,
]);

List<int> vp8(int width, int height) => _riffChunk('VP8 ', [
  0,
  0,
  0,
  0x9D,
  0x01,
  0x2A,
  width & 0xFF,
  width >> 8,
  height & 0xFF,
  height >> 8,
  0,
  0,
]);

List<int> _vp8x(int flags, int width, int height) => _riffChunk('VP8X', [
  flags,
  0,
  0,
  0,
  (width - 1) & 0xFF,
  ((width - 1) >> 8) & 0xFF,
  ((width - 1) >> 16) & 0xFF,
  (height - 1) & 0xFF,
  ((height - 1) >> 8) & 0xFF,
  ((height - 1) >> 16) & 0xFF,
]);

/// A plain WebP whose lossless header declares [width] x [height].
Uint8List webpLossless(int width, int height) => _riff(vp8l(width, height));

/// A plain lossy WebP declaring [width] x [height] (14 bits each).
Uint8List webpLossy(int width, int height) => _riff(vp8(width, height));

/// A WebP that is animated: the animation flag, ANIM and ANMF chunks.
Uint8List webpAnimated({int width = 64, int height = 64, bool flag = true}) =>
    _riff([
      ..._vp8x(flag ? 0x02 : 0, width, height),
      ..._riffChunk('ANIM', [0, 0, 0, 0, 0, 0]),
      ..._riffChunk('ANMF', List.filled(16, 0)),
    ]);

/// An extended WebP: a [canvasWidth] x [canvasHeight] canvas holding a
/// lossless picture that declares [innerWidth] x [innerHeight].
Uint8List webpExtended({
  required int canvasWidth,
  required int canvasHeight,
  required int innerWidth,
  required int innerHeight,
  int flags = 0,
}) => _riff([
  ..._vp8x(flags, canvasWidth, canvasHeight),
  ...vp8l(innerWidth, innerHeight),
]);
