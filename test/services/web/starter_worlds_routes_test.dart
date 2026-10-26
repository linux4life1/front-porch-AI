// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The PWA's starter-world picker talks to these two routes: the index it
// lists, and the add that imports one bundle (root and places) through the
// same repository path as /api/worlds/import.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart';
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

  Future<(int, Map<String, dynamic>)> call(String method, String path) async {
    final res = await router.call(
      shelf.Request(method, Uri.parse('http://localhost$path')),
    );
    final body = await res.readAsString();
    return (
      res.statusCode,
      body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(body) as Map<String, dynamic>,
    );
  }

  test('GET /api/worlds/starter lists the seven with what the picker '
      'shows', () async {
    final (status, body) = await call('GET', '/api/worlds/starter');
    expect(status, 200);
    final rows = (body['starters'] as List).cast<Map<String, dynamic>>();
    expect(rows, hasLength(7));
    final harbor = rows.singleWhere((r) => r['id'] == 'harborside');
    expect(harbor['name'], 'Harborside');
    expect(harbor['blurb'], isNotEmpty);
    expect(harbor['climate'], 'Temperate');
    expect(harbor['places'], 3);
    expect(harbor['added'], isFalse);
  });

  test('POST /api/worlds/starter/<id>/import adds the root and its places '
      'and answers with both', () async {
    final (status, body) = await call(
      'POST',
      '/api/worlds/starter/harborside/import',
    );
    expect(status, 200);
    final world = body['world'] as Map<String, dynamic>;
    expect(world['name'], 'Harborside');
    final names = [
      for (final w in (body['worlds'] as List).cast<Map<String, dynamic>>())
        w['name'],
    ];
    expect(
      names,
      containsAll([
        'Harborside',
        'The Quay',
        'Lantern Street Market',
        'Lighthouse Point',
      ]),
    );
    expect(
      repo.placeWorlds.where((w) => w.parentWorldId == world['id']),
      hasLength(3),
    );
    final (_, index) = await call('GET', '/api/worlds/starter');
    final row = (index['starters'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((r) => r['id'] == 'harborside');
    expect(row['added'], isTrue);
  });

  test('an unknown starter is a 404 and writes nothing', () async {
    for (final id in ['nope', '..%2Findex', 'index']) {
      final (status, _) = await call('POST', '/api/worlds/starter/$id/import');
      expect(status, 404, reason: id);
    }
    expect(repo.placeWorlds, isEmpty);
  });
}
