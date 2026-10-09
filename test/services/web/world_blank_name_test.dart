// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A world with no name showed as "?" on its card and "delete \"\"?" in its
// confirm. No path may create one: the repository refuses a blank name, the
// web route answers 400 in plain words, and an imported file that carries no
// name still imports, under "Imported World".

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart' as model;
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/services/web/facade/world_facade.dart';
import 'package:front_porch_ai/services/web/routes/world_routes.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_docs_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late WorldRepository repo;
  late Router router;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting();
    await db.select(db.characters).get(); // create schema
    final storage = StorageService();
    await storage.setRootPath(
      Directory.systemTemp.createTempSync('fpai_root_').path,
    );
    repo = WorldRepository(storage, db);
    await repo.loadWorlds();
    router = Router();
    WebWorldRoutes(WorldFacade(repo), router);
  });

  tearDown(() => db.close());

  // The real router, in process (dart:io's client is mocked under the binding).
  Future<(int, Map<String, dynamic>)> post(String path, Object body) async {
    final res = await router.call(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost$path'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
    );
    return (
      res.statusCode,
      jsonDecode(await res.readAsString()) as Map<String, dynamic>,
    );
  }

  test('POST /api/worlds with a blank name is a 400 in plain words', () async {
    for (final name in ['', '   ']) {
      final (status, body) = await post('/api/worlds', {'name': name});
      expect(status, 400, reason: 'name "$name"');
      expect(body['error'], 'Give your place a name.');
    }
    expect(await db.getAllWorlds(), isEmpty);
  });

  test('a rename to a blank name over the web keeps the old name', () async {
    var (status, _) = await post('/api/worlds', {'name': 'Harbor Town'});
    expect(status, 200);
    final id = repo.worlds.single.id;

    (status, _) = await post('/api/worlds', {
      'id': id,
      'name': '  ',
      'originalName': 'Harbor Town',
    });
    expect(status, 400);
    expect((await db.getWorldById(id))!.name, 'Harbor Town');
  });

  test('saveWorld refuses a blank name and stores nothing', () async {
    final world = model.World(
      name: '   ',
      lorebook: Lorebook(entries: []),
    );
    await expectLater(
      repo.saveWorld(world),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'Give your world a name.',
        ),
      ),
    );
    expect(await db.getAllWorlds(), isEmpty);
    expect(repo.worlds, isEmpty);
  });

  test('saveWorld trims the name of a new world', () async {
    await repo.saveWorld(
      model.World(
        name: '  Harbor Town  ',
        lorebook: Lorebook(entries: []),
      ),
    );
    expect((await db.getAllWorlds()).single.name, 'Harbor Town');
  });

  test(
    'a world file with no name still imports, as "Imported World"',
    () async {
      // Pins that the blank-name refusal in saveWorld does not reach imports.
      final imported = await repo.importWorldJson({
        'formatVersion': 1,
        'id': 'src-1',
        'name': '  ',
        'lorebooks': [
          {
            'entries': [
              {'key': 'pier', 'content': 'The pier creaks.'},
            ],
          },
        ],
      });
      expect(imported.name, 'Imported World');
      expect((await db.getAllWorlds()).single.name, 'Imported World');
    },
  );
}
