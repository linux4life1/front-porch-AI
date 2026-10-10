// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A JPEG or a still WebP becomes a PNG for a pack, in an isolate that is
// stopped when it takes too long, and that PNG then goes through the same
// checks as any other. Real pictures here; the hostile ones are in
// expression_pack_convert_crafted_test.dart.

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:front_porch_ai/services/expression_pack_base_check.dart';
import 'package:front_porch_ai/services/expression_pack_convert.dart';
import 'package:front_porch_ai/services/expression_pack_prepare.dart';

import '../helpers/crafted_pictures.dart';

img.Image _picture(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, x * 255 ~/ width, y * 255 ~/ height, 90);
    }
  }
  return image;
}

Uint8List _jpeg(int width, int height) =>
    Uint8List.fromList(img.encodeJpg(_picture(width, height)));
Uint8List _webp(int width, int height, {bool lossless = true}) =>
    Uint8List.fromList(
      img.encodeWebP(_picture(width, height), lossless: lossless),
    );
Uint8List _png(int width, int height) =>
    Uint8List.fromList(img.encodePng(_picture(width, height)));

/// What an isolate that never finishes in time does: works for a while, then
/// answers with a picture (which is not what a timeout should return).
void _slowEntry(PackConvertJob job) {
  final until = DateTime.now().add(const Duration(seconds: 4));
  while (DateTime.now().isBefore(until)) {}
  job.reply.send([
    Uint8List.fromList([1]),
    null,
    false,
  ]);
}

/// Works for a moment, then answers with a refusal.
void _briefEntry(PackConvertJob job) {
  final until = DateTime.now().add(const Duration(milliseconds: 250));
  while (DateTime.now().isBefore(until)) {}
  job.reply.send([null, 'done', false]);
}

void _throwingEntry(PackConvertJob job) => throw StateError('decoder blew up');

void _silentEntry(PackConvertJob job) {}

void main() {
  group('a real picture is converted', () {
    test('a JPEG becomes a PNG of the same size', () async {
      final done = await convertPackBase(_jpeg(900, 1200));
      expect(done.refusal, isNull);
      final png = done.png!;
      expect(packPictureKind(png), PackPictureKind.png);
      expect(inspectPackBase(png).size, (900, 1200));
    });

    test('a lossless and a lossy WebP become PNGs', () async {
      for (final lossless in [true, false]) {
        final done = await convertPackBase(_webp(320, 200, lossless: lossless));
        expect(done.refusal, isNull, reason: 'lossless: $lossless');
        expect(inspectPackBase(done.png!).size, (320, 200));
      }
    });

    test('a big one is brought down to a long side of 1536', () async {
      final done = await convertPackBase(_jpeg(3000, 2000));
      expect(inspectPackBase(done.png!).size, (1536, 1024));
      final tall = await convertPackBase(_jpeg(2000, 3000));
      expect(inspectPackBase(tall.png!).size, (1024, 1536));
    });

    test('its EXIF is not read, and it still converts', () async {
      final jpeg = _jpeg(120, 80);
      final exif = [
        0xFF,
        0xE1,
        0x00,
        0x0A,
        0x45,
        0x78,
        0x69,
        0x66,
        0x00,
        0x00,
        0x00,
        0x00,
      ];
      final withExif = Uint8List.fromList([
        ...jpeg.sublist(0, 2),
        ...exif,
        ...jpeg.sublist(2),
      ]);
      final done = await convertPackBase(withExif);
      expect(inspectPackBase(done.png!).size, (120, 80));
    });
  });

  group('preparing a base', () {
    test(
      'a JPEG and a WebP build a 768 base and say they were converted',
      () async {
        final jpeg = await preparePackBase(_jpeg(1200, 900));
        expect((jpeg!.width, jpeg.height, jpeg.converted), (768, 576, true));
        expect(inspectPackBase(jpeg.bytes).size, (768, 576));

        final webp = await preparePackBase(_webp(900, 1200));
        expect((webp!.width, webp.height, webp.converted), (576, 768, true));
      },
    );

    test('a PNG is taken as it was, and not called converted', () async {
      final base = await preparePackBase(_png(1200, 900));
      expect((base!.width, base.height, base.converted), (768, 576, false));
    });

    test('a GIF, a BMP, an animated WebP and junk are refused, asking for a '
        'PNG, JPEG or still WebP', () async {
      final refused = <String>[];
      final things = [
        Uint8List.fromList([...'GIF89a'.codeUnits, 1, 0, 1, 0, 0, 0, 0]),
        Uint8List.fromList([...'BM'.codeUnits, 0, 0, 0, 0, 0, 0, 0, 0]),
        Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]),
        Uint8List(0),
      ];
      for (final bytes in things) {
        expect(
          await preparePackBase(
            bytes,
            onRefused: (r) => refused.add(r.message),
          ),
          isNull,
        );
      }
      expect(refused, hasLength(things.length));
      expect(
        refused,
        everyElement(contains('Please use a PNG, JPEG or still WebP picture')),
      );

      String? animated;
      expect(
        await preparePackBase(
          webpAnimated(),
          onRefused: (r) => animated = r.message,
        ),
        isNull,
      );
      expect(animated, contains('animated'));
    });

    test(
      'a converted picture that is oversized says it is too large',
      () async {
        PackBaseRefusal? got;
        expect(
          await preparePackBase(
            tinyJpeg(16000, 16000),
            onRefused: (r) => got = r,
          ),
          isNull,
        );
        expect(got?.tooLarge, isTrue);
      },
    );
  });

  group('the isolate', () {
    test(
      'a conversion that takes too long is stopped, and is a refusal',
      () async {
        late Isolate spawned;
        final exited = Completer<void>();
        final watch = Stopwatch()..start();
        final done = await convertPackBase(
          Uint8List(8),
          timeout: const Duration(milliseconds: 300),
          entry: _slowEntry,
          onSpawn: (isolate) {
            spawned = isolate;
            final port = ReceivePort();
            isolate.addOnExitListener(port.sendPort);
            port.first.then((_) => exited.complete());
          },
        );
        watch.stop();

        expect(done.png, isNull);
        expect(done.refusal!.message, contains('took too long'));
        expect(done.refusal!.tooLarge, isFalse);
        expect(watch.elapsedMilliseconds, lessThan(2500));
        await exited.future.timeout(
          const Duration(milliseconds: 1500),
          onTimeout: () => fail('the isolate was left running: $spawned'),
        );
      },
    );

    test(
      'a real conversion that runs out of time is stopped the same way',
      () async {
        late Isolate spawned;
        final exited = Completer<void>();
        final done = await convertPackBase(
          _jpeg(2400, 1800),
          timeout: const Duration(milliseconds: 1),
          onSpawn: (isolate) {
            spawned = isolate;
            final port = ReceivePort();
            isolate.addOnExitListener(port.sendPort);
            port.first.then((_) => exited.complete());
          },
        );
        expect(done.refusal?.message, contains('took too long'));
        await exited.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () => fail('the isolate was left running: $spawned'),
        );
      },
    );

    test(
      'only one conversion runs at a time, the rest wait their turn',
      () async {
        // An isolate is counted from its spawn until it has exited. The exit
        // is heard through onExit (the listener given at spawn), not a
        // listener added after: a dying isolate tells its listeners one by
        // one, so a late one can hear it after the next isolate has spawned.
        var running = 0;
        var mostAtOnce = 0;
        final all = await Future.wait([
          for (var i = 0; i < 3; i++)
            convertPackBase(
              Uint8List(8),
              entry: _briefEntry,
              onSpawn: (_) {
                running++;
                mostAtOnce = running > mostAtOnce ? running : mostAtOnce;
              },
              onExit: () => running--,
            ),
        ]);
        expect(all.map((c) => c.refusal?.message), ['done', 'done', 'done']);
        expect(mostAtOnce, 1);
        expect(running, 0);
      },
    );

    test('a conversion that fails does not hold up the next one', () async {
      await convertPackBase(Uint8List(8), entry: _throwingEntry);
      final next = await convertPackBase(Uint8List(8), entry: _briefEntry);
      expect(next.refusal?.message, 'done');
    });

    test('a decoder that throws is a refusal, not a crash', () async {
      final done = await convertPackBase(Uint8List(8), entry: _throwingEntry);
      expect(done.png, isNull);
      expect(done.refusal, isNotNull);
      expect(done.refusal!.tooLarge, isFalse);
    });

    test('an isolate that ends without an answer is a refusal', () async {
      final done = await convertPackBase(Uint8List(8), entry: _silentEntry);
      expect(done.refusal, isNotNull);
    });

    test(
      'a file over the byte limit is refused as too large, unread',
      () async {
        final done = await convertPackBase(Uint8List(kMaxConvertBytes + 1));
        expect(done.refusal!.tooLarge, isTrue);
      },
    );

    test('the original bytes are left as they were', () async {
      final jpeg = _jpeg(200, 100);
      final copy = Uint8List.fromList(jpeg);
      await preparePackBase(jpeg);
      expect(jpeg, copy);
    });
  });
}
