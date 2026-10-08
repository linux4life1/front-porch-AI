// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// After a reload KoboldCpp could not load, where the old model is kept
// running, the phone names the model that runs: the model list's "Loaded"
// badge, the status, and the Local model card (its model and its preset) all
// go back to it, whether the pick was a model switch (which waits for the
// load) or a preset pick (which answers first and loads behind its answer).
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
  late String oldPreset;
  late String brokenModel;

  LocalModelInfo info(String path) => LocalModelInfo(
    path: path,
    filename: p.basename(path),
    sizeBytes: 36,
    modified: DateTime(2026),
  );

  setUp(() async {
    root = Directory.systemTemp.createTempSync('fpai phone running model');
    rig = await KoboldRig.start(root);
    oldModel = rig.gguf('old.gguf');
    oldPreset = rig.preset('Old.kcpps', {'contextsize': 8192}).path;
    // Not a GGUF: a fresh start would be refused, so the engine is kept.
    brokenModel = (File(
      p.join(root.path, 'broken.gguf'),
    )..writeAsBytesSync('XXXX'.codeUnits + List.filled(32, 0))).path;
    final b = rig.storage.backendSettings;
    await b.setLastUsedModelPath(oldModel);
    await b.setActiveKcppsPath(oldPreset);
    await rig.storage.presetSettings.setModelPreset(oldModel, oldPreset);
    // What a launch recorded, and what KoboldCpp goes back to.
    rig.kobold.noteAdminLoadedPair(modelPath: oldModel, kcppsPath: oldPreset);
    rig.engine.model = rig.engine.startupModel = 'koboldcpp/old';
    rig.engine.failing.add(kStagedChatConfig);
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

  Future<List<String>> loadedModels() async {
    final models = await call('GET', '/api/backend/models');
    return [
      for (final m in models['models'] as List)
        if ((m as Map)['loaded'] == true) m['name'] as String,
    ];
  }

  test('a model switch KoboldCpp could not load: the list, the status and '
      'the card still name the model that runs', () async {
    final before = await call('GET', '/api/backend/local-model');

    final body = await call('POST', '/api/backend/models/switch', {
      'path': brokenModel,
    });

    expect(body['refused'], contains('The previous one is still running'));
    expect(await loadedModels(), ['old.gguf']);
    final status = await call('GET', '/api/backend/status');
    expect(status['loadedModel'], 'old.gguf');
    final card = await call('GET', '/api/backend/local-model');
    expect(card['modelName'], before['modelName']);
    expect((card['preset'] as Map)['path'], oldPreset);
  });

  test('a preset pick KoboldCpp could not load, answered before it '
      'loaded: the card goes back to the preset and model that run', () async {
    final before = await call('GET', '/api/backend/local-model');
    final owns = rig.preset('Owns.kcpps', {
      'model_param': brokenModel,
      'contextsize': 8192,
    });

    final answer = await call('POST', '/api/backend/local-model/preset', {
      'path': owns.path,
    });
    expect(
      (answer['preset'] as Map)['path'],
      owns.path,
      reason: 'the answer comes first, with the pick',
    );

    final deadline = DateTime.now().add(const Duration(seconds: 10));
    var card = await call('GET', '/api/backend/local-model');
    while ((card['preset'] as Map?)?['path'] != oldPreset) {
      if (DateTime.now().isAfter(deadline)) {
        fail('the card never went back: ${card['preset']}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      card = await call('GET', '/api/backend/local-model');
    }

    expect(card['modelName'], before['modelName']);
    expect('${card['statusMessage']}', contains('could not load broken.gguf'));
    expect(await loadedModels(), ['old.gguf']);
  });
}
