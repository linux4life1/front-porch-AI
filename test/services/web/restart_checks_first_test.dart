// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The phone's Restart asks whether the start can go ahead BEFORE it stops the
// running KoboldCpp, as the desktop's Start and Restart buttons do. A model
// file that has gone (moved, an unplugged drive) or a preset the app will not
// start from used to stop the working engine first, and then the start was
// refused: chat had no engine until the user fixed it. Now the engine keeps
// running and the answer says why in `refused`, which the Models page shows
// beside the buttons.
//
// The real facade and routes run on the real LLM provider, against a
// KoboldCpp on loopback; a fresh start is counted, not run.

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

void main() {
  late Directory root;
  late KoboldRig rig;
  late AppDatabase db;
  late Router router;
  late String model;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('fpai restart checks first');
    rig = await KoboldRig.start(root);
    model = rig.gguf('chat.gguf');
    await rig.storage.backendSettings.setLastUsedModelPath(model);
    db = AppDatabase.forTesting();
    router = Router();
    WebBackendRoutes(
      WebServerDeps(storage: rig.storage, db: db, auth: AuthService(db)),
      router,
      backend: BackendFacade(
        rig.provider,
        rig.storage,
        FakeModelManager(
          localModels: [
            LocalModelInfo(
              path: model,
              filename: p.basename(model),
              sizeBytes: 36,
              modified: DateTime(2026),
            ),
          ],
        ),
      ),
    );
  });

  tearDown(() async {
    await rig.close();
    await db.close();
    root.deleteSync(recursive: true);
  });

  Future<Map<String, dynamic>> restart() async {
    final res = await router.call(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost/api/backend/restart'),
        headers: {'content-type': 'application/json'},
        body: '{}',
      ),
    );
    expect(res.statusCode, 200);
    return jsonDecode(await res.readAsString()) as Map<String, dynamic>;
  }

  test('the model file has gone: the running engine is not stopped, and the '
      'answer says why', () async {
    File(model).deleteSync();

    final body = await restart();

    expect(body['refused'], allOf(isA<String>(), contains('chat.gguf')));
    expect(body['running'], isTrue, reason: 'the engine still runs');
    expect(rig.kobold.running, isTrue);
    expect(rig.kobold.launches, 0, reason: 'it was never stopped to restart');
  });

  test('a preset the app will not start from: the running engine is not '
      'stopped, and the answer says why', () async {
    final preset = rig.preset('Theirs.kcpps', {
      'contextsize': 8192,
      'remotetunnel': true,
    });
    await rig.storage.backendSettings.setActiveKcppsPath(preset.path);

    final body = await restart();

    expect(body['refused'], contains('remotetunnel'));
    expect(body['running'], isTrue);
    expect(rig.kobold.launches, 0);
  });

  test('with nothing in the way, Restart restarts as before', () async {
    final body = await restart();

    expect(body['refused'], isNull);
    expect(rig.kobold.launches, 1);
  });
}
