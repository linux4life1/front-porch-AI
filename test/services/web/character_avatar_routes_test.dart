// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The portrait / expression-label / ZIP-import verbs the web never had, at
// the route boundary: raw bytes in, status codes out. The facade behaviour is
// covered in character_authoring_test.dart; this pins what a stale or
// hostile client sees.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/character_authoring_facade.dart';
import 'package:front_porch_ai/services/web/facade/character_facade.dart';
import 'package:front_porch_ai/services/web/routes/character_avatar_routes.dart';
import 'package:front_porch_ai/services/web/util/request_body.dart';

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
  late StorageService storage;
  late CharacterAuthoringFacade auth;
  late Router router;
  late String id;

  const pngBase64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
      'z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting();
    await db.select(db.characters).get();
    storage = StorageService();
    await storage.setRootPath(
      Directory.systemTemp.createTempSync('fpai_root_').path,
    );
    final repo = CharacterRepository(db, storage);
    final chars = CharacterFacade(db, storage, null, null, repo);
    auth = CharacterAuthoringFacade(repo, storage);
    router = Router();
    WebCharacterAvatarRoutes(auth, router);
    final created = await chars.create({'name': 'Edith'});
    id = created!['id'] as String;
  });

  tearDown(() => db.close());

  Future<shelf.Response> post(String path, {Object? body}) => router.call(
    shelf.Request('POST', Uri.parse('http://localhost$path'), body: body),
  );

  test('portrait: raw bytes land, an empty upload is a 400', () async {
    final res = await post(
      '/api/characters/$id/portrait',
      body: base64Decode(pngBase64),
    );
    expect(res.statusCode, 200);

    final empty = await post('/api/characters/$id/portrait', body: <int>[]);
    expect(empty.statusCode, 400);
  });

  test('portrait: an unknown character is a 404', () async {
    final res = await post(
      '/api/characters/nope/portrait',
      body: base64Decode(pngBase64),
    );
    expect(res.statusCode, 404);
  });

  test('portrait: an oversized body is a 413', () async {
    final res = await router.call(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost/api/characters/$id/portrait'),
        headers: {'content-length': '${RequestBody.uploadMaxBytes + 1}'},
        body: Stream<List<int>>.value([1]),
      ),
    );
    expect(res.statusCode, 413);
  });

  test('label: a known emotion re-tags, an unknown one is a 400', () async {
    await auth.addAvatar(id, [1, 2, 3, 4], 'joy');
    final avatarId = (await auth.avatars(id)).first['id'] as String;

    final ok = await post(
      '/api/characters/$id/avatars/$avatarId/label',
      body: jsonEncode({'label': 'anger'}),
    );
    expect(ok.statusCode, 200);
    expect((await auth.avatars(id)).first['label'], 'anger');

    final bad = await post(
      '/api/characters/$id/avatars/$avatarId/label',
      body: jsonEncode({'label': 'not-a-label'}),
    );
    expect(bad.statusCode, 400);
  });

  test('label: a missing avatar is a 404', () async {
    final res = await post(
      '/api/characters/$id/avatars/nope/label',
      body: jsonEncode({'label': 'joy'}),
    );
    expect(res.statusCode, 404);
  });

  test('import-zip: tagged images land, the rest is counted', () async {
    final zip = ZipEncoder().encode(
      Archive()
        ..addFile(ArchiveFile('joy.png', 4, [1, 2, 3, 4]))
        ..addFile(ArchiveFile('sunset.png', 4, [5, 6, 7, 8])),
    );
    final res = await post(
      '/api/characters/$id/expressions/import-zip',
      body: zip,
    );
    expect(res.statusCode, 200);
    final body = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
    expect(body['added'], 1);
    expect(body['unrecognized'], 1);
    expect((body['avatars'] as List).length, 1);
  });

  test('import-zip: an unknown character is a 404', () async {
    final zip = ZipEncoder().encode(
      Archive()..addFile(ArchiveFile('joy.png', 4, [1, 2, 3, 4])),
    );
    final res = await post(
      '/api/characters/nope/expressions/import-zip',
      body: zip,
    );
    expect(res.statusCode, 404);
  });

  test('import-zip: an oversized body is a 413', () async {
    final res = await router.call(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost/api/characters/$id/expressions/import-zip'),
        headers: {'content-length': '${RequestBody.uploadMaxBytes + 1}'},
        body: Stream<List<int>>.value([1]),
      ),
    );
    expect(res.statusCode, 413);
  });

  test('import-zip: a pack that unpacks past the cap is a 413', () async {
    // The header declares 65 MiB; the cap refuses it before decompression.
    final zip = ZipEncoder().encode(
      Archive()..addFile(ArchiveFile('joy.png', 65 * 1024 * 1024, [1, 2, 3])),
    );
    final res = await post(
      '/api/characters/$id/expressions/import-zip',
      body: zip,
    );
    expect(res.statusCode, 413);
  });
}
