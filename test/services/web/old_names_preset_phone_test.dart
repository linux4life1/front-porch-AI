// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A preset an older KoboldCpp saved, with old setting names and not the
// current ones, is refused wherever the phone can put it to use, with the
// reason in plain words, the same words the desktop says (see
// kcpps_old_names_test):
//
// - picking it as chat's preset answers 422 with the reason, and it does not
//   become chat's preset;
// - switching to a model whose preset it is answers the switch with the
//   reason in `refused`, and the Local model card carries it in its status
//   line.
//
// The real facade and routes run on the real LLM provider, against a
// KoboldCpp on loopback that records what it is asked to reload.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/facade/backend_facade.dart';
import 'package:front_porch_ai/services/web/routes/backend_routes.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';

import '../../golden/support/fakes_services.dart';
import '../kobold/loopback_kobold.dart';

Matcher _refusal(List<String> names) => allOf([
  for (final n in names) contains(n),
  contains('saved by an older KoboldCpp'),
  contains('updated once'),
  contains('press Save'),
  contains('pick another preset'),
]);

void main() {
  late Directory root;
  late KoboldRig rig;
  late AppDatabase db;
  late Router router;
  late String chatModel;
  late String otherModel;

  LocalModelInfo info(String path) => LocalModelInfo(
    path: path,
    filename: p.basename(path),
    sizeBytes: 36,
    modified: DateTime(2026),
  );

  setUp(() async {
    root = Directory.systemTemp.createTempSync('fpai old names phone');
    rig = await KoboldRig.start(root);
    chatModel = rig.gguf('chat.gguf');
    otherModel = rig.gguf('other.gguf');
    await rig.storage.backendSettings.setLastUsedModelPath(chatModel);
    db = AppDatabase.forTesting();
    router = Router();
    WebBackendRoutes(
      WebServerDeps(storage: rig.storage, db: db, auth: AuthService(db)),
      router,
      backend: BackendFacade(
        rig.provider,
        rig.storage,
        FakeModelManager(localModels: [info(chatModel), info(otherModel)]),
      ),
    );
  });

  tearDown(() async {
    await rig.close();
    await db.close();
    root.deleteSync(recursive: true);
  });

  Future<shelf.Response> post(String path, Map<String, dynamic> body) =>
      router.call(
        shelf.Request(
          'POST',
          Uri.parse('http://localhost$path'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode(body),
        ),
      );

  Future<Map<String, dynamic>> json(shelf.Response res) async =>
      jsonDecode(await res.readAsString()) as Map<String, dynamic>;

  test('picking an old-style preset is refused with its reason: it is not '
      'chat\'s preset and the engine is never asked to load it', () async {
    final old = rig.preset('Old.kcpps', {
      'contextsize': 8192,
      'usecublas': ['normal', '0'],
      'blasbatchsize': 2048,
    });

    final res = await post('/api/backend/local-model/preset', {
      'path': old.path,
    });
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(res.statusCode, 422);
    expect(
      (await json(res))['error'],
      _refusal(['usecublas', 'blasbatchsize']),
    );
    expect(rig.storage.backendSettings.activeKcppsPath, isNull);
    expect(rig.engine.reloads, isEmpty);
    expect(rig.kobold.running, isTrue);
  });

  test('a preset with both spellings is picked as before', () async {
    final fine = rig.preset('Fine.kcpps', {
      'contextsize': 8192,
      'usecuda': ['normal', '0'],
      'usecublas': ['normal', '0'],
    });

    final res = await post('/api/backend/local-model/preset', {
      'path': fine.path,
    });

    expect(res.statusCode, 200);
    expect(rig.storage.backendSettings.activeKcppsPath, fine.path);
  });

  test('switching to a model whose preset is old-style: the answer says why '
      'in "refused", the old model keeps running, and the Local model card '
      'carries the reason in its status line', () async {
    final old = rig.preset('Old.kcpps', {
      'contextsize': 8192,
      'flashattention': false,
    });
    await rig.storage.presetSettings.setModelPreset(otherModel, old.path);

    final res = await post('/api/backend/models/switch', {'path': otherModel});
    final body = await json(res);

    expect(res.statusCode, 200);
    expect(
      body['refused'],
      allOf(
        contains('The previous one is still running'),
        _refusal(['flashattention']),
      ),
    );
    expect(body['running'], isTrue, reason: 'the old model still runs');
    expect(rig.engine.reloads, isEmpty, reason: 'KoboldCpp was never asked');

    final card = await json(
      await router.call(
        shelf.Request(
          'GET',
          Uri.parse('http://localhost/api/backend/local-model'),
        ),
      ),
    );
    expect(card['statusMessage'], _refusal(['flashattention']));
  });
}
