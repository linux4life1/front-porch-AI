// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Stoop card art on desktop goes through the same two things the hub site
// does: the postcard thumb for tiles (`?v=thumb`) and a cache so a picture
// is fetched once. No server here — the cache test proves bytes come from
// disk because the API it holds points at a port nothing listens on.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/backporch/backporch.dart';

void main() {
  group('stoopAssetPath', () {
    test('tiles ask for the hub thumb variant, the card page the original', () {
      expect(stoopAssetPath('abc', thumb: true), '/assets/abc/raw?v=thumb');
      expect(stoopAssetPath('abc'), '/assets/abc/raw');
    });

    test('client URL and relay path agree', () {
      final api = BackporchApi(baseUrl: 'https://hub.example');
      expect(
        api.assetUrl('a b', thumb: true),
        'https://hub.example${stoopAssetPath('a b', thumb: true)}',
      );
      expect(api.assetUrl('a b', thumb: true), contains('/assets/a%20b/raw'));
    });
  });

  group('StoopAssetCache', () {
    late Directory dir;
    late StoopAssetCache cache;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('fpai_stoop_assets_');
      cache = StoopAssetCache(
        dir: dir,
        // 9 is the discard port; nothing answers, so any fetch would throw.
        api: BackporchApi(baseUrl: 'http://127.0.0.1:9'),
      );
    });

    tearDown(() => dir.delete(recursive: true));

    test(
      'serves a cached thumb from disk without touching the network',
      () async {
        final bytes = Uint8List.fromList([1, 2, 3, 4]);
        File(p.join(dir.path, 'asset-1.t')).writeAsBytesSync(bytes);

        expect(await cache.has('asset-1', thumb: true), isTrue);
        expect(await cache.bytes('asset-1', thumb: true, token: 'x'), bytes);
      },
    );

    test('thumb and original are separate entries', () async {
      File(p.join(dir.path, 'asset-1.t')).writeAsBytesSync([1]);

      expect(await cache.has('asset-1', thumb: true), isTrue);
      expect(await cache.has('asset-1', thumb: false), isFalse);
      // The original is not on disk, so this has to fetch — and cannot.
      expect(
        () => cache.bytes('asset-1', thumb: false, token: 'x'),
        throwsA(anything),
      );
    });

    test('a half-written file is never served', () async {
      File(p.join(dir.path, 'asset-1.t.part')).writeAsBytesSync([1]);
      expect(await cache.has('asset-1', thumb: true), isFalse);
    });

    test('sign-out forgets every cached picture', () async {
      final shared = StoopAssetCache.shared(dir);
      File(p.join(dir.path, 'asset-1.t')).writeAsBytesSync([1]);
      expect(await shared.has('asset-1', thumb: true), isTrue);

      await StoopAssetCache.forgetAll();
      expect(await shared.has('asset-1', thumb: true), isFalse);
      expect(dir.existsSync(), isFalse);
      dir.createSync(); // so tearDown has something to delete
    });
  });
}
