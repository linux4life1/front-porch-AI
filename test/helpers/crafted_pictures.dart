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

/// A PNG whose header appears twice: the first is small, the second huge, and
/// the decoder takes its size from the last.
Uint8List pngWithTwoHeaders({
  int firstWidth = 4,
  int firstHeight = 4,
  int secondWidth = 16000,
  int secondHeight = 16000,
}) => Uint8List.fromList([
  ..._pngSignature,
  ...pngHeader(firstWidth, firstHeight),
  ...pngHeader(secondWidth, secondHeight),
  ...pngChunk('IDAT', zeroZlib(firstHeight * (1 + firstWidth * 4))),
  ...pngChunk('IEND', const []),
]);
