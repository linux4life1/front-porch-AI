// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// What the phone is told when chat's model or preset could not be loaded
// into the running KoboldCpp. KoboldCpp goes back to the model it had, and
// the app keeps that engine when a fresh start would be refused (see
// kobold_reload_keeps_engine_test):
//
// - switching model waits for the load, so its answer carries the refusal in
//   `refused` (additive: a phone that does not know the field ignores it);
// - picking a preset answers at once and loads behind the answer, so the
//   reason reaches the phone through the Local model card, which carries the
//   status line the desktop shows.
//
// The real facade and routes run on the real LLM provider, against a
// KoboldCpp on loopback that goes back to its own model for a config it
// cannot load.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/facade/backend_facade.dart';
import 'package:front_porch_ai/services/web/routes/backend_routes.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';

import '../../golden/support/fakes_services.dart';
import '../kobold/loopback_kobold.dart';

void main() {
  late Directory root;
  late KoboldRig rig;
  late AppDatabase db;
  late Router router;
  late String oldModel;
  late String brokenModel;

  LocalModelInfo info(String path) => LocalModelInfo(
    path: path,
    filename: p.basename(path),
    sizeBytes: 36,
    modified: DateTime(2026),
  );

  setUp(() async {
    root = Directory.systemTemp.createTempSync('fpai reload refusal');
    rig = await KoboldRig.start(root);
    oldModel = rig.gguf('old.gguf');
    // Not a GGUF: a fresh start would be refused, so the engine is kept.
    brokenModel = (File(
      p.join(root.path, 'broken.gguf'),
    )..writeAsBytesSync('XXXX'.codeUnits + List.filled(32, 0))).path;
    await rig.storage.backendSettings.setLastUsedModelPath(oldModel);
    db = AppDatabase.forTesting();
    router = Router();
    WebBackendRoutes(
      WebServerDeps(storage: rig.storage, db: db, auth: AuthService(db)),
      router,
      backend: BackendFacade(
        rig.provider,
        rig.storage,
        FakeModelManager(localModels: [info(oldModel), info(brokenModel)]),
      ),
    );
  });

  tearDown(() async {
    await rig.close();
    await db.close();
    root.deleteSync(recursive: true);
  });

  Future<Map<String, dynamic>> call(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final res = await router.call(
      shelf.Request(
        method,
        Uri.parse('http://localhost$path'),
        headers: {'content-type': 'application/json'},
        body: body == null ? null : jsonEncode(body),
      ),
    );
    expect(res.statusCode, 200);
    return jsonDecode(await res.readAsString()) as Map<String, dynamic>;
  }

  test('switching to a model KoboldCpp cannot load: the old model keeps '
      'running, and the answer says why in "refused"', () async {
    // KoboldCpp could not load it either: it goes back to its own model.
    rig.engine.failing.add(kStagedChatConfig);

    final body = await call('POST', '/api/backend/models/switch', {
      'path': brokenModel,
    });

    expect(
      body['refused'],
      allOf(
        contains('The new model was not loaded'),
        contains('The previous one is still running'),
        contains('Not a valid GGUF'),
      ),
    );
    expect(body['running'], isTrue, reason: 'the old model still runs');
    expect(rig.kobold.running, isTrue);
    expect(
      body.containsKey('phase'),
      isTrue,
      reason: 'the status is as before',
    );
  });

  test('switching to a model that loads has no refusal', () async {
    final body = await call('POST', '/api/backend/models/switch', {
      'path': oldModel,
    });

    expect(body.containsKey('refused'), isTrue);
    expect(body['refused'], isNull);
  });

  test('picking a preset whose model cannot be loaded: the pick is '
      'answered at once, and the Local model card then carries the '
      'reason', () async {
    rig.engine.failing.add(kStagedChatConfig);
    final owns = rig.preset('Owns.kcpps', {
      'model_param': brokenModel,
      'contextsize': 8192,
    });

    await call('POST', '/api/backend/local-model/preset', {'path': owns.path});

    final deadline = DateTime.now().add(const Duration(seconds: 10));
    var card = await call('GET', '/api/backend/local-model');
    while (!'${card['statusMessage']}'.contains('could not load broken.gguf')) {
      if (DateTime.now().isAfter(deadline)) {
        fail('the card never said why: ${card['statusMessage']}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      card = await call('GET', '/api/backend/local-model');
    }

    expect(card['running'], isTrue, reason: 'the old model keeps running');
    expect(rig.kobold.running, isTrue);
  });
}
