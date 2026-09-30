// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';

/// A valid, tiny-on-disk PNG that declares a huge blank picture: [width] x
/// [height], one bit per pixel. Decoding it would take seconds and memory in
/// proportion to the pixels, though the file is a few tens of kilobytes.
Uint8List hugePng(int width, int height) {
  final rowBytes = (width + 7) ~/ 8;
  final raw = Uint8List(height * (rowBytes + 1)); // filter 0 + blank row
  final idat = ZLibEncoder().convert(raw);
  final out = BytesBuilder();
  out.add([137, 80, 78, 71, 13, 10, 26, 10]);
  void chunk(String type, List<int> data) {
    final body = [...type.codeUnits, ...data];
    final length = ByteData(4)..setUint32(0, data.length);
    out.add(length.buffer.asUint8List());
    out.add(body);
    final crc = ByteData(4)..setUint32(0, _crc32(body));
    out.add(crc.buffer.asUint8List());
  }

  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 1) // bit depth
    ..setUint8(9, 0); // grayscale
  chunk('IHDR', header.buffer.asUint8List());
  chunk('IDAT', idat);
  chunk('IEND', const []);
  return out.toBytes();
}

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}
