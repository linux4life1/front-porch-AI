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
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/character_facade.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory' ||
            call.method == 'getTemporaryDirectory') {
          return Directory.systemTemp.createTempSync('fpai_byaf_web_').path;
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CharacterFacade.importBytes — .byaf gallery', () {
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

    test('imports every extra image as a gallery look', () async {
      final bytes = _byafBytes(
        name: 'Byaf Gallery',
        images: [_png(10, 20, 30), _png(40, 50, 60), _png(70, 80, 90)],
      );

      final result = await facade.importBytes(bytes, 'gallery.byaf');
      expect(result, isNotNull);
      expect(result!['name'], 'Byaf Gallery');
      expect(result['looksImported'], 2);

      final id = result['id'] as String;
      final looks = (await repo.getAvatarImages(id)).where((a) => a.isLook);
      expect(looks, hasLength(2));
    });

    test('rejects a zip that is not a .byaf archive', () async {
      final junk = ZipEncoder().encode(
        Archive()..addFile(ArchiveFile.string('readme.txt', 'nope')),
      );
      expect(await facade.importBytes(junk, 'fake.byaf'), isNull);
    });

    test('returns name_collision without writing looks when ask', () async {
      final first = await facade.importBytes(
        _byafBytes(name: 'Twin', images: [_png(1, 2, 3)]),
        'one.byaf',
      );
      expect(first, isNotNull);

      final second = await facade.importBytes(
        _byafBytes(name: 'Twin', images: [_png(4, 5, 6), _png(7, 8, 9)]),
        'two.byaf',
        collision: 'ask',
      );
      expect(second?['status'], 'name_collision');
      expect(repo.characters.where((c) => c.name == 'Twin'), hasLength(1));
      final looks = await repo.getAvatarImages(first!['id'] as String);
      expect(looks.where((a) => a.isLook), isEmpty);
    });
  });
  group('CharacterFacade.importBytes — .byaf chat persona', () {
    late AppDatabase db;
    late StorageService storage;
    late CharacterRepository repo;
    late UserPersonaService personas;
    late CharacterFacade facade;
    late String rowanId;

    List<int> chatByaf(String name) {
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
            jsonEncode({'displayName': name, 'persona': 'A quiet painter.'}),
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'scenarios/scenario1.json',
            jsonEncode({
              'schemaVersion': 1,
              'firstMessages': [
                {'text': 'Hi {user}.'},
              ],
              'messages': [
                {
                  'type': 'ai',
                  'outputs': [
                    {'text': "You worry too much, rowan."},
                  ],
                },
                {'type': 'human', 'text': 'rowan grins.'},
              ],
            }),
          ),
        );
      return ZipEncoder().encode(archive);
    }

    setUp(() async {
      _setupPathProviderMock();
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting();
      storage = StorageService();
      await storage.initialized;
      repo = CharacterRepository(db, storage);
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      await Future<void>.delayed(Duration.zero);
      while (repo.isLoading) {
        if (DateTime.now().isAfter(deadline)) fail('repo did not settle');
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      personas = UserPersonaService(db);
      while (personas.personas.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await personas.createPersona('', 'Sam', '', null);
      rowanId = await personas.createPersona('', 'Rowan', '', null);
      facade = CharacterFacade(db, storage, null, null, repo)
        ..importPersonas = personas;
    });

    tearDown(() async {
      personas.dispose();
      await db.close();
    });

    test('ask returns persona_pick with the named persona and writes '
        'nothing', () async {
      final result = await facade.importBytes(
        chatByaf('Juniper'),
        'juniper.byaf',
        persona: 'ask',
      );
      expect(result?['status'], 'persona_pick');
      expect(result?['recommendedPersonaId'], rowanId);
      expect(repo.characters.where((c) => c.name == 'Juniper'), isEmpty);
    });

    test('a picked persona is who the imported chat speaks as', () async {
      final result = await facade.importBytes(
        chatByaf('Juniper'),
        'juniper.byaf',
        persona: rowanId,
      );
      final sessions = await db.getSessionsForCharacter(
        result!['id'] as String,
      );
      expect(sessions.single.userPersonaId, rowanId);
      final rows = await db.getMessagesForSession(sessions.single.id);
      expect(rows.first.swipes, contains('Hi Rowan.'));
      final mine = rows.where((r) => r.isUser).single;
      expect(mine.sender, 'Rowan');
    });

    test('an older app that never asks gets the default persona', () async {
      final result = await facade.importBytes(
        chatByaf('Juniper'),
        'juniper.byaf',
      );
      final sessions = await db.getSessionsForCharacter(
        result!['id'] as String,
      );
      expect(sessions.single.userPersonaId, personas.defaultPersonaId);
    });
    test('every chat in the archive comes across, under the pick', () async {
      Map<String, dynamic> chat(String title, String line) => {
        'schemaVersion': 1,
        'title': title,
        'firstMessages': [
          {'characterID': 'c1', 'text': 'Hi {user}.'},
        ],
        'messages': [
          {'type': 'human', 'text': line},
        ],
      };
      final archive = Archive()
        ..addFile(
          ArchiveFile.string(
            'manifest.json',
            jsonEncode({
              'characters': ['characters/char1/character.json'],
              'scenarios': ['scenarios/a.json', 'scenarios/b.json'],
            }),
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'characters/char1/character.json',
            jsonEncode({'displayName': 'Juniper', 'persona': 'A painter.'}),
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'scenarios/a.json',
            jsonEncode(chat('Harbour', 'rowan waves.')),
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'scenarios/b.json',
            jsonEncode(chat('Rain', 'rowan sits.')),
          ),
        );

      final result = await facade.importBytes(
        ZipEncoder().encode(archive),
        'juniper.byaf',
        persona: rowanId,
      );
      expect(result?['chats'], 2);
      final sessions = await db.getSessionsForCharacter(
        result!['id'] as String,
      );
      expect(sessions.map((x) => x.name).toSet(), {'Harbour', 'Rain'});
      for (final x in sessions) {
        expect(x.userPersonaId, rowanId);
      }
    });
  });
}
