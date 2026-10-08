// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// One rule for who sets the context (maintainer ruling O, 2026-10-05): the
// chosen preset does, while KoboldCpp is the backend and a preset is chosen
// (koboldPresetOwnsContext). The phone's Settings save already followed it
// (settings_context_lock_test). The Local model card's context route refused
// on any backend once a preset path was set, so a preset left chosen on a
// remote backend locked the user's own context there. It now follows the
// same rule.
//
// The real facade and routes, on the real LLM provider and storage.

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
  test('the rule: KoboldCpp is the backend and a preset is chosen', () {
    for (final (backend, preset, owns) in [
      ('kobold', '/p/Long chats.kcpps', true),
      // An old stored name runs KoboldCpp too.
      ('pseudoRemote', '/p/Long chats.kcpps', true),
      ('kobold', null, false),
      ('kobold', '', false),
      ('kobold', '  ', false),
      ('openRouter', '/p/Long chats.kcpps', false),
      ('omlx', '/p/Long chats.kcpps', false),
    ]) {
      expect(
        koboldPresetOwnsContext(backend: backend, kcppsPath: preset),
        owns,
        reason: '$backend, $preset',
      );
    }
  });

  group('the Local model card\'s context', () {
    late Directory root;
    late KoboldRig rig;
    late AppDatabase db;
    late Router router;

    setUp(() async {
      root = Directory.systemTemp.createTempSync('fpai local context lock');
      rig = await KoboldRig.start(root);
      final model = rig.gguf('chat.gguf');
      await rig.storage.backendSettings.setLastUsedModelPath(model);
      await rig.storage.backendSettings.setContextSize(16384);
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

    Future<int> setContext(int tokens) async {
      final res = await router.call(
        shelf.Request(
          'POST',
          Uri.parse('http://localhost/api/backend/local-model/context'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'context': tokens}),
        ),
      );
      return res.statusCode;
    }

    Future<void> choosePreset(String backend) async {
      final preset = rig.preset('Long chats.kcpps', {'contextsize': 32768});
      await rig.storage.backendSettings.setActiveKcppsPath(preset.path);
      await rig.storage.backendSettings.setBackendType(backend);
    }

    test('KoboldCpp with a preset: the preset sets it, and another is '
        'refused', () async {
      await choosePreset('kobold');

      expect(await setContext(24576), 400);
      expect(rig.storage.backendSettings.contextSize, 32768);
    });

    test('a preset left chosen on a remote backend: the context is the '
        'user\'s to set', () async {
      await choosePreset('openRouter');

      expect(await setContext(24576), 200);
      expect(rig.storage.backendSettings.contextSize, 24576);
    });
  });
}
