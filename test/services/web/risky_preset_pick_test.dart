// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The phone picks chat's preset from the presets in the engine folder. A
// preset that would make KoboldCpp run a program or open itself to the
// internet is refused at the pick, with the reason in plain words: it does
// not become chat's preset, and the running engine is never asked to load
// it. A good preset is still picked and loaded as before.
//
// The real facade and routes run on the real LLM provider, against a
// KoboldCpp on loopback that records what it is asked to reload.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart';
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

  setUp(() async {
    root = Directory.systemTemp.createTempSync('fpai risky pick');
    rig = await KoboldRig.start(root);
    await rig.storage.backendSettings.setLastUsedModelPath(rig.gguf('m.gguf'));
    db = AppDatabase.forTesting();
    router = Router();
    WebBackendRoutes(
      WebServerDeps(storage: rig.storage, db: db, auth: AuthService(db)),
      router,
      backend: BackendFacade(rig.provider, rig.storage, FakeModelManager()),
    );
  });

  tearDown(() async {
    await rig.close();
    await db.close();
    root.deleteSync(recursive: true);
  });

  Future<shelf.Response> pick(String path) => router.call(
    shelf.Request(
      'POST',
      Uri.parse('http://localhost/api/backend/local-model/preset'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'path': path}),
    ),
  );

  /// The engine is asked for a reload as soon as the pick is acted on; a
  /// moment is enough for that to show.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 300));

  /// Waits for what the pick sets going behind its answer.
  Future<void> until(bool Function() done) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!done()) {
      if (DateTime.now().isAfter(deadline)) fail('KoboldCpp never loaded it');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  test('a risky preset is refused with its reason: it is not chat\'s preset '
      'and the engine is never asked to load it', () async {
    final risky = rig.preset('Risky.kcpps', {
      'contextsize': 8192,
      'mcpfile': 'https://example.com/servers.json',
      'remotetunnel': true,
    });

    final res = await pick(risky.path);
    await settle();

    expect(res.statusCode, 422);
    final error = jsonDecode(await res.readAsString())['error'] as String;
    expect(error, contains('mcpfile'));
    expect(error, contains('remotetunnel'));
    expect(error, contains('pick another preset'));
    expect(rig.storage.backendSettings.activeKcppsPath, isNull);
    expect(rig.engine.reloads, isEmpty);
    expect(rig.kobold.running, isTrue);
  });

  test('a good preset is still picked, and loaded into the running '
      'engine', () async {
    final good = rig.preset('Good.kcpps', {
      'contextsize': 8192,
      'mcpfile': '',
      'remotetunnel': false,
    });

    final res = await pick(good.path);

    expect(res.statusCode, 200);
    expect(rig.storage.backendSettings.activeKcppsPath, good.path);
    await until(() => rig.engine.model == 'koboldcpp/m');
    expect(rig.engine.reloads, [kStagedChatConfig]);
  });
}
