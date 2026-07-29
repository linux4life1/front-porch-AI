// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:front_porch_ai/utils/world_cover.dart';

void main() {
  test('encodeWorldCoverDataUrl produces decodable jpeg data URL', () {
    final image = img.Image(width: 32, height: 24);
    img.fill(image, color: img.ColorRgb8(200, 100, 50));
    final png = Uint8List.fromList(img.encodePng(image));
    final url = encodeWorldCoverDataUrl(png);
    expect(url, isNotNull);
    expect(url!, startsWith('data:image/jpeg;base64,'));
    final back = decodeWorldCoverBytes(url);
    expect(back, isNotNull);
    expect(back!.length, greaterThan(20));
  });

  test('decode rejects empty / garbage', () {
    expect(decodeWorldCoverBytes(null), isNull);
    expect(decodeWorldCoverBytes(''), isNull);
    expect(decodeWorldCoverBytes('not-a-cover'), isNull);
  });

  test('isWorldCoverDataUrl', () {
    expect(isWorldCoverDataUrl('data:image/jpeg;base64,abc'), isTrue);
    expect(isWorldCoverDataUrl('/tmp/foo.jpg'), isFalse);
  });
}
