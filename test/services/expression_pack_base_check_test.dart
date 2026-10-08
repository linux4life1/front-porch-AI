// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A pack's base picture reaches no image decoder until its own bytes have been
// judged: PNG, JPEG and still WebP only, nothing animated, nothing over about
// 40 megapixels (size read from the file, not from the decoder), a PNG that
// inflates to no more than its size holds, and a decode that fails is "not a
// picture", not an error. Each hostile file here is a few KB or less and
// declares or inflates to something enormous; each must be refused at once,
// with nothing large allocated.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:front_porch_ai/services/expression_pack_base_check.dart';
import 'package:front_porch_ai/services/expression_pack_service.dart';

import '../helpers/crafted_pictures.dart';
import '../helpers/huge_png.dart';

/// What a refusal cost: the verdict, how long it took, and how much the
/// process's peak memory grew while it was made.
({PackBaseVerdict verdict, int ms, int peakGrowthMb}) _judge(Uint8List bytes) {
  final before = ProcessInfo.maxRss;
  final watch = Stopwatch()..start();
  final verdict = inspectPackBase(bytes);
  watch.stop();
  return (
    verdict: verdict,
    ms: watch.elapsedMilliseconds,
    peakGrowthMb: (ProcessInfo.maxRss - before) ~/ (1024 * 1024),
  );
}

void _refusedAtOnce(Uint8List bytes, {bool? tooLarge, String? saying}) {
  final r = _judge(bytes);
  expect(r.verdict.size, isNull, reason: 'it must not be accepted');
  expect(r.ms, lessThan(500), reason: 'refused from its bytes, not decoded');
  expect(r.peakGrowthMb, lessThan(150), reason: 'nothing large allocated');
  if (tooLarge != null) {
    expect(r.verdict.refusal?.tooLarge, tooLarge);
  }
  if (saying != null) {
    expect(r.verdict.refusal?.message, contains(saying));
  }
}

void main() {
  group('a PNG', () {
    test('64x64 whose data inflates to hundreds of megabytes is refused '
        'while inflating, and stops at once', () {
      final bomb = pngBomb(inflated: 256 * 1024 * 1024);
      expect(bomb.length, lessThan(1024 * 1024));
      _refusedAtOnce(bomb);
    });

    test('is accepted when its data is exactly what its size holds, and '
        'within a small margin of it', () {
      expect(inspectPackBase(pngWithExtra(64, 48)).size, (64, 48));
      expect(inspectPackBase(pngWithExtra(64, 48, extra: 1000)).size, (64, 48));
      expect(inspectPackBase(pngWithExtra(64, 48, extra: 5000)).size, isNull);
    });

    test('interlaced, the bound is the sum of its seven passes', () {
      // 5x3 RGBA: passes of 5, 5, 0, 5, 13, 18 and 21 bytes = 67 by hand.
      Uint8List interlaced(int inflated) => Uint8List.fromList([
        137, 80, 78, 71, 13, 10, 26, 10, //
        ...pngHeader(5, 3, interlace: 1),
        ...pngChunk('IDAT', zeroZlib(inflated)),
        ...pngChunk('IEND', const []),
      ]);
      expect(inspectPackBase(interlaced(67)).size, (5, 3));
      expect(inspectPackBase(interlaced(67 + 2000)).size, isNull);
    });

    test('over 40 megapixels is refused from its header', () {
      _refusedAtOnce(
        hugePng(16000, 16000),
        tooLarge: true,
        saying: '16000x16000',
      );
    });

    test('is judged at the limit, not near it', () {
      // Only the size is under test here: a stream shorter than its size holds
      // is left for the decoder to fail on.
      expect(
        inspectPackBase(pngBomb(width: 6400, height: 6250, inflated: 100)).size,
        (6400, 6250),
      );
      expect(
        inspectPackBase(
          pngBomb(width: 6401, height: 6250, inflated: 100),
        ).refusal?.tooLarge,
        isTrue,
      );
    });

    test('two headers, a small one and then a huge one, are refused: the '
        'decoder takes the size from the last', () {
      _refusedAtOnce(pngWithTwoHeaders());
      _refusedAtOnce(pngWithTwoHeaders(secondWidth: 4, secondHeight: 4));
    });

    test('an APNG is refused, whatever its frames declare', () {
      _refusedAtOnce(
        apng(frameWidth: 16000, frameHeight: 16000),
        tooLarge: false,
        saying: 'animated',
      );
      _refusedAtOnce(
        apng(frames: 30, frameWidth: 6000, frameHeight: 6000),
        tooLarge: false,
        saying: 'animated',
      );
    });

    test('a bad header, colour type or depth is not a picture', () {
      _refusedAtOnce(
        Uint8List.fromList([
          137, 80, 78, 71, 13, 10, 26, 10, //
          ...pngHeader(4, 4, depth: 7),
          ...pngChunk('IEND', const []),
        ]),
      );
      _refusedAtOnce(
        Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13]),
      );
    });
  });

  group('anything that is not a PNG', () {
    final jpeg = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 900, height: 1200)),
    );
    // A real 1x1 lossless WebP.
    final webp = Uint8List.fromList(
      base64Decode('UklGRhoAAABXRUJQVlA4TA0AAAAvAAAAEAcQERGIiP4HAA=='),
    );

    test('a real JPEG is refused, and asked to be a PNG', () {
      expect(jpeg.sublist(0, 3), [0xFF, 0xD8, 0xFF]);
      _refusedAtOnce(jpeg, tooLarge: false, saying: 'Please use a PNG');
    });

    test('a real WebP is refused, and asked to be a PNG', () {
      expect(String.fromCharCodes(webp, 8, 12), 'WEBP');
      _refusedAtOnce(webp, tooLarge: false, saying: 'Please use a PNG');
    });

    test(
      'a GIF, a BMP and bytes that are nothing are refused the same way',
      () {
        _refusedAtOnce(
          Uint8List.fromList([...'GIF89a'.codeUnits, 1, 0, 1, 0, 0, 0, 0]),
          saying: 'Please use a PNG',
        );
        _refusedAtOnce(
          Uint8List.fromList([...'BM'.codeUnits, 0, 0, 0, 0, 0, 0, 0, 0]),
          saying: 'Please use a PNG',
        );
        _refusedAtOnce(Uint8List(0), saying: 'Please use a PNG');
        _refusedAtOnce(
          Uint8List.fromList([1, 2, 3]),
          saying: 'Please use a PNG',
        );
      },
    );
  });

  group('making the base', () {
    test('a good PNG becomes a 768 base, landscape or portrait', () {
      final wide = Uint8List.fromList(
        img.encodePng(img.Image(width: 1200, height: 900)),
      );
      final tall = Uint8List.fromList(
        img.encodePng(img.Image(width: 900, height: 1200)),
      );
      expect(normalizePackBase(wide).let((b) => (b!.width, b.height)), (
        768,
        576,
      ));
      expect(normalizePackBase(tall).let((b) => (b!.width, b.height)), (
        576,
        768,
      ));
    });

    test('a JPEG is given back as a refusal and nothing is decoded', () {
      PackBaseRefusal? got;
      final jpg = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 900, height: 1200)),
      );
      expect(normalizePackBase(jpg, onRefused: (r) => got = r), isNull);
      expect(got?.message, contains('Please use a PNG'));
    });

    test('a refusal is given to the caller, and nothing is decoded', () {
      PackBaseRefusal? got;
      final watch = Stopwatch()..start();
      final base = normalizePackBase(
        hugePng(16000, 16000),
        onRefused: (r) => got = r,
      );
      expect(base, isNull);
      expect(got?.tooLarge, isTrue);
      expect(watch.elapsedMilliseconds, lessThan(1000));
    });

    test('a decode that fails is "not a picture", never an error', () {
      // The right size, but its first scanline names a filter that does not
      // exist: it passes every check and then fails in the decoder.
      final rows = Uint8List(8 * (1 + 8 * 4))..[0] = 9;
      final broken = Uint8List.fromList([
        137, 80, 78, 71, 13, 10, 26, 10, //
        ...pngHeader(8, 8),
        ...pngChunk('IDAT', ZLibEncoder().convert(rows)),
        ...pngChunk('IEND', const []),
      ]);
      expect(inspectPackBase(broken).size, (8, 8));

      PackBaseRefusal? got;
      expect(normalizePackBase(broken, onRefused: (r) => got = r), isNull);
      expect(got, isNull, reason: 'no reason to show beyond "not a picture"');
    });
  });
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
