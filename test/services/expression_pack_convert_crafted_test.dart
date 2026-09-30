// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Small files built to make a JPEG or WebP decoder allocate gigabytes, judged
// through the whole conversion (the isolate included). Each must come back a
// refusal at once, with nothing large allocated. This file holds no test that
// decodes anything large on purpose, so the process's peak memory says whether
// a decoder was let loose.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:front_porch_ai/services/expression_pack_convert.dart';
import 'package:front_porch_ai/services/expression_pack_jpeg_check.dart';

import '../helpers/crafted_pictures.dart';

Future<void> _refusedAtOnce(
  Uint8List bytes, {
  bool? tooLarge,
  String? saying,
}) async {
  final before = ProcessInfo.maxRss;
  final watch = Stopwatch()..start();
  final done = await convertPackBase(bytes);
  watch.stop();
  final grewMb = (ProcessInfo.maxRss - before) ~/ (1024 * 1024);

  expect(done.png, isNull, reason: 'it must not be accepted');
  expect(done.refusal, isNotNull);
  expect(watch.elapsedMilliseconds, lessThan(2000), reason: 'refused quickly');
  expect(grewMb, lessThan(150), reason: 'nothing large was allocated');
  if (tooLarge != null) expect(done.refusal!.tooLarge, tooLarge);
  if (saying != null) expect(done.refusal!.message, contains(saying));
}

Uint8List _realJpeg([int width = 64, int height = 64]) =>
    Uint8List.fromList(img.encodeJpg(img.Image(width: width, height: height)));

/// Where the two bytes [a], [b] first appear in [bytes].
int _find(Uint8List bytes, int a, int b) {
  for (var i = 0; i + 1 < bytes.length; i++) {
    if (bytes[i] == a && bytes[i + 1] == b) return i;
  }
  throw StateError('marker not found');
}

void main() {
  group('a JPEG', () {
    test(
      'of a few dozen bytes declaring 16000x16000 is refused as too large',
      () async {
        final tiny = tinyJpeg(16000, 16000);
        expect(tiny.length, lessThan(64));
        await _refusedAtOnce(tiny, tooLarge: true, saying: '16000x16000');
      },
    );

    test(
      'with a frame header hidden in an unknown segment is refused',
      () async {
        final hidden = jpegWithHiddenFrame(_realJpeg(), 7000, 7000);
        await _refusedAtOnce(hidden, tooLarge: false);
      },
    );
  });

  group('a WebP', () {
    test('of 74 bytes with the top bits of its size set is refused as too '
        'large', () async {
      final bits = webpLossyTopBits(0x4000 | 64, 0x4000 | 64);
      expect(bits.length, 74);
      await _refusedAtOnce(bits, tooLarge: true, saying: '16448x16448');
    });

    test('with a small picture chunk and then a huge one is refused', () async {
      final dual = webpChunks([vp8l(64, 64), vp8l(16383, 16383)]);
      await _refusedAtOnce(dual, tooLarge: true, saying: '16383x16383');
    });

    test('that is animated is refused', () async {
      await _refusedAtOnce(webpAnimated(), tooLarge: false, saying: 'animated');
    });
  });

  group('a JPEG that is read strictly', () {
    void refused(String name, Uint8List bytes) => test('$name is refused', () {
      expect(() => checkJpeg(bytes), throwsA(isA<PackPictureRefused>()));
    });

    final real = _realJpeg();
    final sof = _find(real, 0xFF, 0xC0);
    final sos = _find(real, 0xFF, 0xDA);
    final eoi = real.length - 2;

    test('a real one passes, and comes out the size it says', () {
      expect(real.sublist(eoi), [0xFF, 0xD9]);
      final checked = checkJpeg(real);
      expect((checked.width, checked.height), (64, 64));
    });

    refused(
      'a second frame header',
      Uint8List.fromList([
        ...real.sublist(0, sos),
        ...real.sublist(sof, sof + 19),
        ...real.sublist(sos),
      ]),
    );
    refused(
      'a frame header after the scan',
      Uint8List.fromList([
        ...real.sublist(0, eoi),
        ...real.sublist(sof, sof + 19),
        ...real.sublist(eoi),
      ]),
    );
    refused(
      'a segment of a kind it does not know',
      Uint8List.fromList([
        ...real.sublist(0, sof),
        0xFF, 0xF0, 0x00, 0x04, 1, 2, //
        ...real.sublist(sof),
      ]),
    );
    refused(
      'an application segment after the scan',
      Uint8List.fromList([
        ...real.sublist(0, eoi),
        0xFF, 0xE1, 0x00, 0x04, 1, 2, //
        ...real.sublist(eoi),
      ]),
    );
    refused(
      'a stray byte between two segments',
      Uint8List.fromList([...real.sublist(0, sof), 0x00, ...real.sublist(sof)]),
    );
    refused('one with no end', Uint8List.sublistView(real, 0, eoi));
    refused('a scan before any frame header', () {
      final copy = Uint8List.fromList(real);
      copy[sof + 1] = 0xE2; // the frame header becomes an application segment
      return copy;
    }());
    refused('a size of nothing', () {
      final copy = Uint8List.fromList(real);
      copy[sof + 5] = 0;
      copy[sof + 6] = 0;
      return copy;
    }());

    refused(
      'four components',
      Uint8List.fromList([
        ...real.sublist(0, sof),
        0xFF, 0xC0, 0x00, 0x14, 0x08, 0x00, 0x40, 0x00, 0x40, 0x04, //
        0x01, 0x11, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01, 0x04, 0x11, 0x01,
        ...real.sublist(sof + 19),
      ]),
    );

    for (final (name, at, value) in [
      ('12-bit samples', 4, 12),
      ('a sampling factor of 5', 11, 0x55),
    ]) {
      refused(name, () {
        final copy = Uint8List.fromList(real);
        copy[sof + at] = value;
        return copy;
      }());
    }
  });
}
