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
          return Directory.systemTemp.createTempSync('fpai_inplace_gal_').path;
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

Future<Uint8List> _v2PngBytes({
  required String name,
  String? stableId,
  String description = 'png card',
}) async {
  final dir = Directory.systemTemp.createTempSync('fpai_v2png_');
  final path = p.join(dir.path, 'card.png');
  await V2CardService().saveCardAsPng(
    CharacterCard(
      name: name,
      description: description,
      frontPorchExtensions: stableId == null
          ? null
          : FrontPorchExtensions(stableId: stableId),
    ),
    path,
    null,
  );
  final bytes = Uint8List.fromList(await File(path).readAsBytes());
  await dir.delete(recursive: true);
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('in-place import clears prior gallery looks', () {
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

    Future<int> lookCount(String id) async =>
        (await repo.getAvatarImages(id)).where((a) => a.isLook).length;

    test(
      'stableId silent reimport (no collision=replace) drops byaf looks',
      () async {
        final first = await facade.importBytes(
          _byafBytes(
            name: 'Stable',
            images: [_png(1, 2, 3), _png(10, 20, 30), _png(40, 50, 60)],
          ),
          'a.byaf',
        );
        expect(first, isNotNull);
        expect(first!['looksImported'], 2);
        final id = first['id'] as String;
        expect(await lookCount(id), 2);

        final stableId = repo.characters
            .singleWhere((c) => c.dbId == id)
            .frontPorchExtensions
            ?.stableId;
        expect(stableId, isNotNull);

        // Renamed incoming card, same stableId — the web name-collision block
        // is skipped; importCharacter still updates in place.
        final second = await facade.importBytes(
          await _v2PngBytes(
            name: 'Stable Renamed',
            stableId: stableId,
            description: 'silent reimport',
          ),
          'b.png',
        );
        expect(second, isNotNull);
        expect(second!['id'], id);
        expect(second['replaced'], isNull);
        expect(
          await lookCount(id),
          0,
          reason: 'gallery must be the new card only',
        );
      },
    );

    test('PNG Replace after byaf leaves zero looks', () async {
      final first = await facade.importBytes(
        _byafBytes(
          name: 'Swap',
          images: [_png(1, 2, 3), _png(10, 20, 30), _png(40, 50, 60)],
        ),
        'a.byaf',
      );
      expect(first!['looksImported'], 2);
      final id = first['id'] as String;

      final second = await facade.importBytes(
        await _v2PngBytes(name: 'Swap', description: 'png replace'),
        'b.png',
        collision: 'replace',
        replaceId: id,
      );
      expect(second, isNotNull);
      expect(second!['replaced'], isTrue);
      expect(second['id'], id);
      expect(await lookCount(id), 0);
    });

    test('Keep both PNG does not strip the byaf card looks', () async {
      final first = await facade.importBytes(
        _byafBytes(name: 'Twin', images: [_png(1, 1, 1), _png(2, 2, 2)]),
        'a.byaf',
      );
      final second = await facade.importBytes(
        await _v2PngBytes(name: 'Twin'),
        'b.png',
        collision: 'keepBoth',
      );
      expect(second!['replaced'], isNull);
      expect(second['id'], isNot(first!['id']));
      expect(await lookCount(first['id'] as String), 1);
    });
  });
}
