// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The user's own chat length comes back on the phone too (maintainer ruling
// I, 2026-10-05; kobold_own_context_comes_back_test has the rule). The
// phone's preset picker and its model switch go through the same place as
// the desktop's, so going back to automatic, or switching to a model with no
// preset of its own, puts back the context the user picked on the Local
// model card.
//
// The real facade and routes, on the real LLM provider and storage, against
// a KoboldCpp on loopback.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/facade/backend_facade.dart';
import 'package:front_porch_ai/services/web/routes/backend_routes.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';

import '../../golden/support/fakes_services.dart';
import '../kobold/loopback_kobold.dart';

/// The two models, whose headers the Local model card reads for real.
class _Models extends FakeModelManager {
  _Models(List<LocalModelInfo> models) : super(localModels: models);

  @override
  Future<GGUFModelInfo?> getModelArchitectureInfo(String filePath) =>
      GGUFParser.getModelArchitectureInfo(filePath);
}

void main() {
  late Directory root;
  late KoboldRig rig;
  late AppDatabase db;
  late Router router;
  late String model;
  late String other;

  LocalModelInfo info(String path) => LocalModelInfo(
    path: path,
    filename: p.basename(path),
    sizeBytes: 36,
    modified: DateTime(2026),
  );

  setUp(() async {
    root = Directory.systemTemp.createTempSync('fpai own context phone');
    rig = await KoboldRig.start(root);
    model = rig.gguf('chat.gguf');
    other = rig.gguf('other.gguf');
    await rig.storage.backendSettings.setLastUsedModelPath(model);
    db = AppDatabase.forTesting();
    router = Router();
    WebBackendRoutes(
      WebServerDeps(storage: rig.storage, db: db, auth: AuthService(db)),
      router,
      backend: BackendFacade(
        rig.provider,
        rig.storage,
        _Models([info(model), info(other)]),
      ),
    );
  });

  tearDown(() async {
    // A pick reloads the running engine, which acts on it half a second
    // later, reading the staged file: let it, before the files go.
    await Future<void>.delayed(const Duration(seconds: 1));
    await rig.close();
    await db.close();
    root.deleteSync(recursive: true);
  });

  Future<int> post(String path, Map<String, dynamic> body) async {
    final res = await router.call(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost$path'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
    );
    return res.statusCode;
  }

  int saved() => rig.storage.backendSettings.contextSize;

  /// The user's own, picked on the Local model card, then a 32k preset.
  Future<void> ownThenPreset() async {
    expect(
      await post('/api/backend/local-model/context', {'context': 65536}),
      200,
    );
    final preset = rig.preset('Long chats.kcpps', {'contextsize': 32768});
    expect(
      await post('/api/backend/local-model/preset', {'path': preset.path}),
      200,
    );
    expect(saved(), 32768, reason: 'the preset\'s, while it is chosen');
    // The running engine takes the preset half a second after it is asked.
    await Future<void>.delayed(const Duration(seconds: 1));
  }

  test('back to automatic puts back the user\'s own context', () async {
    await ownThenPreset();

    expect(await post('/api/backend/local-model/preset', {'path': null}), 200);

    expect(saved(), 65536);
  });

  test('switching to a model with no preset of its own puts back the user\'s '
      'own context', () async {
    await ownThenPreset();

    expect(await post('/api/backend/models/switch', {'path': other}), 200);

    expect(rig.storage.backendSettings.activeKcppsPath, isNull);
    expect(saved(), 65536);
  });
}
