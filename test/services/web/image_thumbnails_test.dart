// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Unit coverage for ThumbnailCache — the web-UI avatar downscaler. Exercises
// the pure byte-generation core (resize, JPEG-vs-PNG format selection, no
// upscaling, and disk-cache reuse) without needing an HTTP request.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:front_porch_ai/services/web/util/image_thumbnails.dart';

void main() {
  late Directory cacheDir;
  late Directory srcDir;
  late ThumbnailCache cache;

  setUp(() {
    cacheDir = Directory.systemTemp.createTempSync('fpa_thumb_cache_');
    srcDir = Directory.systemTemp.createTempSync('fpa_thumb_src_');
    cache = ThumbnailCache(cacheDir);
  });

  tearDown(() {
    if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
    if (srcDir.existsSync()) srcDir.deleteSync(recursive: true);
  });

  File writePng(String name, img.Image image) {
    final f = File('${srcDir.path}${Platform.pathSeparator}$name');
    f.writeAsBytesSync(img.encodePng(image));
    return f;
  }

  img.Image opaque(int w, int h) {
    final im = img.Image(width: w, height: h);
    img.fill(im, color: img.ColorRgb8(120, 80, 160));
    return im;
  }

  img.Image transparent(int w, int h) {
    final im = img.Image(width: w, height: h, numChannels: 4);
    img.fill(im, color: img.ColorRgba8(120, 80, 160, 0));
    return im;
  }

  test('opaque source is downscaled to a JPEG at the requested width', () async {
    final src = writePng('big.png', opaque(1000, 1500));
    final originalSize = src.lengthSync();

    final thumb = await cache.bytesFor(src, 400);

    expect(thumb.contentType, 'image/jpeg');
    final decoded = img.decodeImage(thumb.bytes)!;
    expect(decoded.width, 400);
    expect(decoded.height, 600); // aspect preserved
    expect(
      thumb.bytes.length,
      lessThan(originalSize),
      reason: 'thumbnail must be smaller than the full-resolution source',
    );
  });

  test('source with real transparency stays a PNG', () async {
    final src = writePng('alpha.png', transparent(300, 300));

    final thumb = await cache.bytesFor(src, 256);

    expect(thumb.contentType, 'image/png');
    final decoded = img.decodeImage(thumb.bytes)!;
    expect(decoded.width, 256);
    expect(decoded.hasAlpha, isTrue);
  });

  test('smaller-than-requested source is never upscaled', () async {
    final src = writePng('small.png', opaque(100, 150));

    final thumb = await cache.bytesFor(src, 400);

    final decoded = img.decodeImage(thumb.bytes)!;
    expect(decoded.width, 100, reason: 'must not upscale beyond source width');
  });

  test('second call hits the on-disk cache and returns identical bytes', () async {
    final src = writePng('cached.png', opaque(800, 800));

    final first = await cache.bytesFor(src, 400);
    // A cache file for this key/format now exists.
    final cachedFiles = cacheDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.jpg'))
        .toList();
    expect(cachedFiles, hasLength(1));

    final second = await cache.bytesFor(src, 400);
    expect(second.contentType, first.contentType);
    expect(second.bytes, equals(first.bytes));
  });

  test('a stale cache entry (older than source) is regenerated cleanly', () async {
    final src = writePng('stale.png', opaque(800, 800));
    await cache.bytesFor(src, 400);

    // Age the cached thumbnail so it predates the source mtime.
    final cached = cacheDir.listSync().whereType<File>().single;
    final sourceMtime = src.statSync().modified;
    cached.setLastModifiedSync(sourceMtime.subtract(const Duration(hours: 1)));

    // Regeneration must produce a valid image (not throw / not serve garbage).
    final regen = await cache.bytesFor(src, 400);
    expect(regen.contentType, 'image/jpeg');
    expect(img.decodeImage(regen.bytes)!.width, 400);
  });
}
