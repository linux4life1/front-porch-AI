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

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late AppDatabase db;
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync(
      'fpai_gallery_portrait_replace_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return tempRoot.path;
          }
          return null;
        });
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(sameIsolate: true);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await db.close();
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  test(
    'gallery replacement changes only pixels and keeps DB plus chara fields',
    () async {
      final storage = StorageService();
      await storage.initialized;
      final repository = CharacterRepository(db, storage);
      while (repository.isLoading) {
        await Future<void>.delayed(Duration.zero);
      }

      final original = CharacterCard(
        name: 'Portrait Test Character',
        description: 'Keeps a complete description.',
        personality: 'Patient and observant.',
        scenario: 'Cataloguing records on the porch.',
        firstMessage: 'The archive is ready.',
        creator: 'Sosuke Aizen',
        creatorNotes: 'Keep this credit attached to the card.',
        characterVersion: '7.4',
        lorebook: Lorebook(
          entries: [
            LorebookEntry(
              key: 'archive',
              content: 'The archive keeps every original record.',
            ),
          ],
        ),
      );
      await storage.charactersDir.create(recursive: true);
      final portraitPath = p.join(
        storage.charactersDir.path,
        'Portrait_Test_Character_111.png',
      );
      final cards = V2CardService();
      await cards.saveCardAsPng(original, portraitPath, null);
      original.imagePath = portraitPath;
      await repository.addCharacter(original);
      await repository.loadCharacters();

      final libraryCard = repository.characters.single;
      expect(
        libraryCard.creator,
        isEmpty,
        reason:
            'The repository intentionally does not hydrate PNG-only credits.',
      );

      // A portrait operation must not flush unrelated, possibly stale,
      // in-memory card state into either the database or the PNG.
      libraryCard
        ..name = 'Unsaved in-memory name'
        ..description = ''
        ..personality = ''
        ..lorebook = null;

      final replacement = img.Image(width: 7, height: 5);
      img.fill(replacement, color: img.ColorRgb8(12, 34, 56));
      final replacementBytes = Uint8List.fromList(img.encodePng(replacement));
      final controller = AvatarGalleryController(
        libraryCard: libraryCard,
        repository: repository,
        storage: storage,
        mode: WardrobeMode.library,
      );

      await controller.replacePortrait(replacementBytes);

      expect(controller.lastError, isNull);
      expect(p.basename(libraryCard.imagePath!), p.basename(portraitPath));
      final pngFiles = await storage.charactersDir
          .list()
          .where(
            (entry) =>
                entry is File &&
                p.extension(entry.path).toLowerCase() == '.png',
          )
          .toList();
      expect(
        pngFiles.map((entry) => p.basename(entry.path)),
        [p.basename(portraitPath)],
        reason:
            'An in-place replacement must not mint a new identity filename.',
      );

      final pixels = img.decodePng(await File(portraitPath).readAsBytes());
      expect(pixels, isNotNull);
      expect((pixels!.width, pixels.height), (7, 5));
      final pixel = pixels.getPixel(0, 0);
      expect((pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()), (12, 34, 56));

      final dbCard = await db.getCharacterById(original.dbId!);
      expect(dbCard.name, original.name);
      expect(dbCard.description, original.description);
      expect(dbCard.personality, original.personality);
      expect(dbCard.lorebook, contains('every original record'));

      final embedded = await cards.readCard(portraitPath);
      expect(embedded, isNotNull);
      expect(embedded!.name, original.name);
      expect(embedded.description, original.description);
      expect(embedded.personality, original.personality);
      expect(
        embedded.lorebook!.entries.single.content,
        'The archive keeps every original record.',
      );
      expect(embedded.creator, 'Sosuke Aizen');
      expect(embedded.creatorNotes, 'Keep this credit attached to the card.');
      expect(embedded.characterVersion, '7.4');

      controller.dispose();
      repository.dispose();
    },
  );
}
