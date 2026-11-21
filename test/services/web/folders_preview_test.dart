// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// GET /api/folders carries `preview` rows — the up-to-4 member portraits the
// desktop folder tile paints as a 2×2 montage (folder_grid_card.dart) and
// the web's portrait tile now draws too (drift ledger #4). The preview must
// carry the same identity fields the character and group grids ride, never
// block on cold file IO, and leave the pre-existing counts untouched
// (relay fields are additive-only — Error Book, has-avatar-redefined).

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/character_facade.dart';
import 'package:front_porch_ai/services/web/facade/character_library_facade.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late AppDatabase db;
  late StorageService storage;
  late CharacterRepository repo;
  late FolderService folders;
  late CharacterLibraryFacade library;
  late List<String> ids;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('fpai_folder_preview_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? root.path
              : null,
        );
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting();
    storage = StorageService();
    await storage.initialized;
    ids = [
      for (final name in ['Ann', 'Bo', 'Cy', 'Dee', 'Eve', 'Fay'])
        await db.insertCharacterReturningId(
          CharactersCompanion(name: Value(name), imagePath: Value('$name.png')),
        ),
    ];
    repo = CharacterRepository(db, storage);
    while (repo.isLoading) {
      await Future<void>.delayed(Duration.zero);
    }
    folders = FolderService(db);
    await folders.reload();
    library = CharacterLibraryFacade(repo, folders, storage, null);
  });

  tearDown(() async {
    folders.dispose();
    repo.dispose();
    storage.dispose();
    await db.close();
    root.deleteSync(recursive: true);
  });

  CharacterFacade facade() => CharacterFacade(db, storage, folders, null, repo);

  Future<Map<String, dynamic>> rowOf(String folderId) async =>
      (await facade().folders()).firstWhere((f) => f['id'] == folderId);

  test('a folder previews its members with the grid identity fields', () async {
    final porch = await folders.createFolder('Porch');
    await library.bulkMove([ids[0], ids[1]], porch.id);

    final row = await rowOf(porch.id);
    final preview = (row['preview'] as List).cast<Map<String, dynamic>>();
    expect(preview.map((p) => p['name']).toSet(), {'Ann', 'Bo'});
    expect(preview.map((p) => p['id']).toSet(), {ids[0], ids[1]});
    for (final p in preview) {
      expect(p['hasAvatar'], isA<bool>());
      expect(p['placeholderPortrait'], isA<bool>());
      expect(p['avatarVersion'], isA<int>());
    }
    // The pre-existing contract rides on untouched.
    expect(row['name'], 'Porch');
    expect(row['characterCount'], 2);
    expect(row['groupCount'], 0);
  });

  test('the preview caps at four — the montage has four cells', () async {
    final porch = await folders.createFolder('Porch');
    await library.bulkMove(ids, porch.id);

    final preview = (await rowOf(porch.id))['preview'] as List;
    expect(preview.length, 4);
  });

  test('an empty folder previews nothing; a card whose file left the library '
      'drops out of the walk', () async {
    final porch = await folders.createFolder('Porch');
    await library.bulkMove([ids[0]], porch.id);
    final ghost = await db.insertCharacterReturningId(
      CharactersCompanion(name: const Value('Ghost')),
    );
    await library.bulkMove([ghost], porch.id);

    final preview =
        (await rowOf(porch.id))['preview'] as List<Map<String, dynamic>>;
    // Ghost has no imagePath, so no filename key resolves it — the tile
    // shows Ann plus the folder glyph fillers, like the desktop walk that
    // skips cards it cannot resolve.
    expect(preview.map((p) => p['name']), ['Ann']);
    expect(
      (await rowOf((await folders.createFolder('Empty')).id))['preview'],
      isEmpty,
    );
  });

  test('the tile counts direct members; the recursive counts stay the '
      'delete dialog\'s', () async {
    // folder_grid_card.dart:91-92 reads the folder's own lists (direct
    // membership; FolderService._load buckets by folderId only), while
    // home_folder_dialogs.dart:121 counts recursively. A nested library
    // must show both numbers distinctly or the tile drifts again.
    final porch = await folders.createFolder('Porch');
    final attic = await folders.createFolder('Attic', parentId: porch.id);
    await library.bulkMove([ids[0]], porch.id);
    await library.bulkMove([ids[1], ids[2]], attic.id);

    final row = await rowOf(porch.id);
    expect(row['directCharacterCount'], 1); // tile line: Ann only
    expect(row['characterCount'], 3); // delete dialog: sweeps subfolders
  });
}
