// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A small file can declare a huge picture. A pack's base is refused from its
// header, before anything is decoded, when it is over about 40 megapixels.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:front_porch_ai/services/expression_pack_service.dart';

import '../helpers/huge_png.dart';

void main() {
  test('a picture over 40 megapixels is refused, with the reason, at once', () {
    final png = hugePng(16000, 16000); // 256 megapixels in a few KB
    expect(png.length, lessThan(1024 * 1024));
    String? why;

    final watch = Stopwatch()..start();
    final result = normalizePackBase(png, onRefused: (r) => why = r);
    watch.stop();

    expect(result, isNull);
    expect(why, contains('16000x16000'));
    expect(why, contains('40 megapixels'));
    expect(
      watch.elapsedMilliseconds,
      lessThan(1000),
      reason: 'refused from the header, not after a decode',
    );
  });

  test('a picture just under the limit is still made into a base', () {
    final png = Uint8List.fromList(
      img.encodePng(img.Image(width: 1200, height: 900)),
    );
    String? why;
    final base = normalizePackBase(png, onRefused: (r) => why = r);
    expect(base, isNotNull);
    expect(why, isNull);
    expect((base!.width, base.height), (768, 576));
  });

  test('bytes that are not a picture are null with no reason given', () {
    String? why;
    expect(
      normalizePackBase(
        Uint8List.fromList([1, 2, 3, 4]),
        onRefused: (r) => why = r,
      ),
      isNull,
    );
    expect(why, isNull);
  });
}
