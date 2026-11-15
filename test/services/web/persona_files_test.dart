// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PR 7d: the persona JSON file pair. A PWA has no folder picker, so the
// desktop's "Import from JSON" and per-persona export travel as bytes over
// POST /api/personas/import and GET /api/personas/<id>/export.json. These
// tests pin the wire contract the phone page leans on: the round trip
// through the same formats the desktop's dialog feeds, the desktop's
// failure copy on an unreadable document, and the desktop's file name on
// the download.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/web/facade/chat_facade.dart';
import 'package:front_porch_ai/services/web/routes/chat_persona_routes.dart';

import '../../golden/support/fakes.dart';

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
  late ChatFacade facade;
  late Router router;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting();
    await db.select(db.characters).get(); // create schema
    final storage = StorageService();
    final personas = UserPersonaService(db);
    facade = ChatFacade(
      FakeChatService(),
      CharacterRepository(db, storage),
      personas,
      null,
      null,
    );
    router = Router();
    registerPersonaRoutes(router, facade);
    // The service seeds a default persona asynchronously on first open;
    // don't race it (Error Book: the seed can take a test's first id).
    while (personas.personas.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  });

  tearDown(() => db.close());

  Future<shelf.Response> post(String path, String body) => router.call(
        shelf.Request('POST', Uri.parse('http://localhost$path'), body: body),
      );

  test('export round-trips: an exported persona re-imports by name',
      () async {
    await facade.createPersona({
      'name': 'Ada Lovelace',
      'persona': 'Counts engines in her head.',
      'title': 'Programmer',
    });
    final created = facade
        .personas()
        .firstWhere((p) => p['name'] == 'Ada Lovelace');

    final out = await facade.personaOps.exportJson(created['id'] as String);
    expect(out, isNotNull);
    // Same name the desktop's export dialog builds.
    expect(out!.filename, 'Ada_Lovelace_FPAIpersona.json');
    final doc = jsonDecode(utf8.decode(out.bytes)) as Map<String, dynamic>;
    expect(doc['personas'], isA<Map<String, dynamic>>());

    // Re-importing the document adds a persona carrying the description
    // back, through the codec's SillyTavern branch.
    final before = facade.personas().length;
    final res = await post('/api/personas/import', utf8.decode(out.bytes));
    expect(res.statusCode, 200);
    final payload = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
    expect(payload['imported'], 'Ada Lovelace');
    final list = (payload['personas'] as List).cast<Map<String, dynamic>>();
    expect(list.length, before + 1);
    expect(
      list.any((p) => p['name'] == 'Ada Lovelace' && p['id'] != created['id']),
      isTrue,
    );
  });

  test('export of an unknown id is 404, not an empty file', () async {
    final res = await router.call(
      shelf.Request(
        'GET',
        Uri.parse('http://localhost/api/personas/nope/export.json'),
      ),
    );
    expect(res.statusCode, 404);
  });

  test('a document matching no format answers 400 with the desktop copy',
      () async {
    final res = await post('/api/personas/import', '{"nonsense": true}');
    expect(res.statusCode, 400);
    final payload = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
    expect(payload['error'], 'Import failed — unrecognized format');
  });

  test('an empty body answers 400 (the desktop\'s "select a file" case)',
      () async {
    final res = await post('/api/personas/import', '   ');
    expect(res.statusCode, 400);
    final payload = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
    expect(payload['error'], 'Please select a file first');
  });

  test('a character card (name + description) imports like the desktop\'s',
      () async {
    final card = jsonEncode({
      'name': 'Cardy',
      'description': 'A tavern card wearing a persona.',
    });
    final res = await post('/api/personas/import', card);
    expect(res.statusCode, 200);
    final payload = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
    expect(payload['imported'], 'Cardy');
  });

  test('the import route wins over the /<id> update catch-all', () async {
    // If /import were shadowed by POST /api/personas/<id>, this would read
    // as an update of persona "import" (404), not a file import (400).
    final res = await post('/api/personas/import', '{"nonsense": true}');
    expect(res.statusCode, 400);
  });
}
