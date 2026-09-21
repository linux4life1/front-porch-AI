// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart' hide AvatarImage;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/character_facade.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory' ||
            call.method == 'getTemporaryDirectory') {
          return Directory.systemTemp.createTempSync('fpai_byaf_repl_').path;
        }
        return null;
      });
}

Uint8List _png(int r, int g, int b) {
  final image = img.Image(width: 8, height: 8);
  img.fill(image, color: img.ColorRgb8(r, g, b));
  image.setPixelRgb(1, 1, 200, 50, 50);
  return Uint8List.fromList(img.encodePng(image));
}

List<int> _byafBytes({required String name, required List<Uint8List> images}) {
  final listed = <Map<String, String>>[
    for (var i = 0; i < images.length; i++) {'path': 'img_$i.png'},
  ];
  final archive = Archive()
    ..addFile(
      ArchiveFile.string(
        'manifest.json',
        jsonEncode({
          'characters': ['characters/char1/character.json'],
          'scenarios': ['scenarios/scenario1.json'],
        }),
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'characters/char1/character.json',
        jsonEncode({
          'displayName': name,
          'persona': '{character} keeps the porch light on.',
          'images': listed,
        }),
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'scenarios/scenario1.json',
        jsonEncode({
          'schemaVersion': 1,
          'narrative': '{character} waits on the porch.',
          'firstMessages': [
            {'text': 'Hello {user}!'},
          ],
        }),
      ),
    );
  for (var i = 0; i < images.length; i++) {
    archive.addFile(
      ArchiveFile('characters/char1/img_$i.png', images[i].length, images[i]),
    );
  }
  return ZipEncoder().encode(archive);
}

List<int> _lookFileBytes(
  StorageService storage,
  CharacterCard card,
  AvatarImage look,
) {
  final safe = card.name
      .replaceAll(RegExp(r'[^\w\s\-]'), '')
      .replaceAll(' ', '_');
  return look.resolveFile(p.join(storage.charactersDir.path, safe)).readAsBytesSync();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Replace .byaf gallery is the new pack only', () {
    late AppDatabase db;
    late StorageService storage;
    late CharacterRepository repo;
    late CharacterFacade facade;

    Future<void> waitSettled() async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (repo.isLoading) {
        if (DateTime.now().isAfter(deadline)) fail('repo did not settle');
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    setUp(() async {
      _setupPathProviderMock();
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting();
      try {
        await db.customStatement(
          'CREATE TABLE IF NOT EXISTS avatar_images ('
          'id TEXT NOT NULL, character_id TEXT NOT NULL, filename TEXT NOT NULL, '
          'label TEXT, display_order INTEGER NOT NULL DEFAULT 0, '
          'created_at INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (id))',
        );
      } catch (_) {}
      storage = StorageService();
      await storage.initialized;
      repo = CharacterRepository(db, storage);
      await Future<void>.delayed(Duration.zero);
      await waitSettled();
      facade = CharacterFacade(db, storage, null, null, repo);
    });

    tearDown(() async => db.close());

    test('Replace A (2 looks) with B (1 look) drops A and keeps B bytes', () async {
      final lookA1 = _png(10, 20, 30);
      final lookA2 = _png(40, 50, 60);
      final lookB1 = _png(70, 80, 90);

      final first = await facade.importBytes(
        _byafBytes(
          name: 'Swap',
          images: [_png(1, 2, 3), lookA1, lookA2],
        ),
        'a.byaf',
      );
      expect(first, isNotNull);
      expect(first!['looksImported'], 2);
      final id = first['id'] as String;

      final second = await facade.importBytes(
        _byafBytes(
          name: 'Swap',
          images: [_png(4, 5, 6), lookB1],
        ),
        'b.byaf',
        collision: 'replace',
        replaceId: id,
      );
      expect(second, isNotNull);
      expect(second!['replaced'], isTrue);
      expect(second['id'], id);
      expect(second['looksImported'], 1);

      final card = repo.characters.singleWhere((c) => c.dbId == id);
      final looks = (await repo.getAvatarImages(id)).where((a) => a.isLook).toList();
      expect(looks, hasLength(1), reason: 'gallery must be B only, not A∪B');
      expect(_lookFileBytes(storage, card, looks.single), lookB1);
    });

    test('Keep both leaves the first character gallery untouched', () async {
      final lookA = _png(11, 22, 33);
      final lookB = _png(44, 55, 66);
      final first = await facade.importBytes(
        _byafBytes(name: 'Twin', images: [_png(1, 1, 1), lookA]),
        'a.byaf',
      );
      final second = await facade.importBytes(
        _byafBytes(name: 'Twin', images: [_png(2, 2, 2), lookB]),
        'b.byaf',
        collision: 'keepBoth',
      );
      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(second!['replaced'], isNull);
      expect(repo.characters.where((c) => c.name == 'Twin'), hasLength(2));

      final firstLooks =
          (await repo.getAvatarImages(first!['id'] as String)).where((a) => a.isLook);
      expect(firstLooks, hasLength(1));
      final firstCard = repo.characters.singleWhere((c) => c.dbId == first['id']);
      expect(_lookFileBytes(storage, firstCard, firstLooks.single), lookA);
    });

    test('Replace with gallery off leaves portrait only', () async {
      final first = await facade.importBytes(
        _byafBytes(
          name: 'Bare',
          images: [_png(9, 9, 9), _png(8, 8, 8), _png(7, 7, 7)],
        ),
        'a.byaf',
      );
      expect(first!['looksImported'], 2);
      final id = first['id'] as String;
      final card = repo.characters.singleWhere((c) => c.dbId == id);

      final cleared = await applyByafGalleryLooks(
        repo: repo,
        imported: card,
        galleryImagePaths: const [],
        importGalleryImages: false,
        replaceExistingLooks: true,
      );
      expect(cleared, 0);
      expect(
        (await repo.getAvatarImages(id)).where((a) => a.isLook),
        isEmpty,
      );
    });
  });
}
