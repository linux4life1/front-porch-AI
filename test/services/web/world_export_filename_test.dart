// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A place id exports its whole world, so the download is named for the
// world the file holds, not the place that was clicked. (Superseded the
// review #599 branch export, which read as the world but dropped its
// sibling places.)

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart' as model;
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/services/web/facade/world_facade.dart';
import 'package:front_porch_ai/services/web/routes/world_routes.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

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
    await db.select(db.characters).get();
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

  Future<model.World> seed(String name, {String? parent}) async {
    final w = model.World(
      name: name,
      lorebook: Lorebook(entries: []),
      climateEnabled: parent == null,
      parentWorldId: parent,
    );
    await repo.saveWorld(w);
    return w;
  }

  test(
    'exporting a location saves its whole world, named for the world',
    () async {
      final earth = await seed('Earth');
      await seed('Asia', parent: earth.id);
      await seed('Europe', parent: earth.id);

      final res = await router.call(
        shelf.Request(
          'GET',
          Uri.parse('http://localhost/api/worlds/Asia/export'),
        ),
      );
      expect(res.statusCode, 200);
      final disposition = res.headers['content-disposition'] ?? '';
      expect(
        disposition,
        contains('Earth.fpworld.json'),
        reason: 'the file holds the whole world, so it is named for it',
      );
      expect(disposition, isNot(contains('Asia')));
      final body = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
      expect(body['name'], 'Earth');
      expect((body['locations'] as List), hasLength(2));
    },
  );

  test('exporting a root still names the file after itself', () async {
    await seed('Earth');
    final res = await router.call(
      shelf.Request(
        'GET',
        Uri.parse('http://localhost/api/worlds/Earth/export'),
      ),
    );
    expect(res.statusCode, 200);
    expect(res.headers['content-disposition'], contains('Earth.fpworld.json'));
  });
}
