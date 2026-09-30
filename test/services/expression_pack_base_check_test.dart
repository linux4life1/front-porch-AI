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

  group('a JPEG', () {
    test('of a few dozen bytes declaring 16000x16000 is refused before any '
        'decoder allocates for it', () {
      final tiny = tinyJpeg(16000, 16000);
      expect(tiny.length, lessThan(64));
      _refusedAtOnce(tiny, tooLarge: true, saying: '16000x16000');
    });

    test('is sized from its frame header, after the APPn segments', () {
      expect(inspectPackBase(tinyJpeg(100, 50)).size, (100, 50));
      expect(inspectPackBase(tinyJpeg(100, 50, sof: 0xC2)).size, (100, 50));
    });

    test('is judged at the limit, not near it', () {
      expect(inspectPackBase(tinyJpeg(6400, 6250)).size, (6400, 6250));
      expect(inspectPackBase(tinyJpeg(6401, 6250)).refusal?.tooLarge, isTrue);
    });

    test('a kind the decoders do not take, or one cut short, is refused', () {
      _refusedAtOnce(tinyJpeg(10, 10, sof: 0xC3), saying: 'PNG, JPEG');
      _refusedAtOnce(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00]));
      _refusedAtOnce(tinyJpeg(0, 10));
    });
  });

  group('a WebP', () {
    test('lossless or lossy, declaring far too much, is refused', () {
      _refusedAtOnce(webpLossless(16000, 16000), tooLarge: true);
      _refusedAtOnce(webpLossy(16383, 16383), tooLarge: true);
    });

    test('animated is refused: by its flag, or by frames without one', () {
      _refusedAtOnce(webpAnimated(), tooLarge: false, saying: 'animated');
      _refusedAtOnce(
        webpAnimated(flag: false),
        tooLarge: false,
        saying: 'animated',
      );
    });

    test('with the animation flag set and no frames, it is still refused', () {
      _refusedAtOnce(
        webpExtended(
          canvasWidth: 64,
          canvasHeight: 64,
          innerWidth: 64,
          innerHeight: 64,
          flags: 0x02,
        ),
        tooLarge: false,
        saying: 'animated',
      );
    });

    test('an extended one is checked at its canvas and at the picture inside '
        'it, and the two must agree', () {
      _refusedAtOnce(
        webpExtended(
          canvasWidth: 64,
          canvasHeight: 64,
          innerWidth: 16000,
          innerHeight: 16000,
        ),
        tooLarge: true,
      );
      _refusedAtOnce(
        webpExtended(
          canvasWidth: 16000,
          canvasHeight: 16000,
          innerWidth: 16000,
          innerHeight: 16000,
        ),
        tooLarge: true,
      );
      _refusedAtOnce(
        webpExtended(
          canvasWidth: 64,
          canvasHeight: 64,
          innerWidth: 32,
          innerHeight: 32,
        ),
      );
      expect(
        inspectPackBase(
          webpExtended(
            canvasWidth: 64,
            canvasHeight: 48,
            innerWidth: 64,
            innerHeight: 48,
          ),
        ).size,
        (64, 48),
      );
    });

    test('two picture chunks, a small one and then a huge one, are refused: '
        'the decoder would keep the last', () {
      _refusedAtOnce(
        webpChunks([vp8l(64, 64), vp8l(16383, 16383)]),
        saying: null,
      );
      // Small first or huge first, lossless or lossy, all the same.
      _refusedAtOnce(webpChunks([vp8l(16383, 16383), vp8l(64, 64)]));
      _refusedAtOnce(webpChunks([vp8(64, 64), vp8l(16383, 16383)]));
      _refusedAtOnce(webpChunks([vp8l(64, 64), vp8(16383, 16383)]));
      _refusedAtOnce(webpChunks([vp8(64, 64), vp8(64, 64)]));
    });

    test('a picture chunk after the end the RIFF header claims is still '
        'seen: the decoder reads to the end of the file', () {
      final first = vp8l(64, 64);
      _refusedAtOnce(
        webpChunks([first, vp8l(16383, 16383)], riffSize: 4 + first.length),
      );
    });

    test('a chunk that runs past the end of the file is refused', () {
      final cut = webpChunks([vp8l(64, 64), vp8l(16383, 16383)]);
      _refusedAtOnce(Uint8List.sublistView(cut, 0, cut.length - 3));
      _refusedAtOnce(
        Uint8List.fromList([
          ...webpLossless(64, 64),
          ...'VP8L'.codeUnits,
          0xFF,
          0xFF,
          0xFF,
          0x7F,
        ]),
      );
    });

    test('one picture chunk is still fine', () {
      expect(inspectPackBase(webpChunks([vp8l(64, 64)])).size, (64, 64));
    });

    test('a second extended header is refused', () {
      final header = webpExtended(
        canvasWidth: 64,
        canvasHeight: 64,
        innerWidth: 64,
        innerHeight: 64,
      ).sublist(12, 12 + 18);
      expect(inspectPackBase(webpChunks([header, vp8l(64, 64)])).size, (
        64,
        64,
      ));
      _refusedAtOnce(webpChunks([header, header, vp8l(64, 64)]));
    });

    test('two picture chunks are refused even when both are small', () {
      _refusedAtOnce(webpChunks([vp8l(64, 64), vp8l(64, 64)]));
      _refusedAtOnce(webpChunks([vp8(64, 64), vp8(64, 64)]));
      _refusedAtOnce(webpChunks([vp8(64, 64), vp8l(64, 64)]));
      _refusedAtOnce(webpChunks([vp8l(64, 64), vp8(64, 64)]));
    });

    test('a cut-off chunk after the picture is refused', () {
      _refusedAtOnce(
        Uint8List.fromList([
          ...webpLossless(64, 64),
          ...'JUNK'.codeUnits,
          100,
          0,
          0,
          0,
          1,
          2,
        ]),
      );
    });

    test('a still one is read for its size', () {
      expect(inspectPackBase(webpLossless(640, 480)).size, (640, 480));
      expect(inspectPackBase(webpLossy(640, 480)).size, (640, 480));
      final tiny = base64Decode(
        'UklGRhoAAABXRUJQVlA4TA0AAAAvAAAAEAcQERGIiP4HAA==',
      );
      expect(inspectPackBase(Uint8List.fromList(tiny)).size, (1, 1));
    });
  });

  group('anything else', () {
    test('a picture of another kind says which kinds are taken', () {
      _refusedAtOnce(
        Uint8List.fromList([...'GIF89a'.codeUnits, 1, 0, 1, 0, 0, 0, 0]),
        saying: 'PNG, JPEG',
      );
      _refusedAtOnce(
        Uint8List.fromList([...'BM'.codeUnits, 0, 0, 0, 0, 0, 0, 0, 0]),
        saying: 'PNG, JPEG',
      );
    });

    test('bytes that are nothing are not a picture', () {
      expect(inspectPackBase(Uint8List(0)).size, isNull);
      expect(inspectPackBase(Uint8List.fromList([1, 2, 3])).refusal, isNull);
    });
  });

  group('making the base', () {
    test('a good PNG and a good JPEG become a 768 base', () {
      final png = Uint8List.fromList(
        img.encodePng(img.Image(width: 1200, height: 900)),
      );
      final jpg = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 900, height: 1200)),
      );
      expect(normalizePackBase(png).let((b) => (b!.width, b.height)), (
        768,
        576,
      ));
      expect(normalizePackBase(jpg).let((b) => (b!.width, b.height)), (
        576,
        768,
      ));
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
