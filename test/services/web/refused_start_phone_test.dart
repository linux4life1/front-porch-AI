// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The phone's Restart and model switch start the app's KoboldCpp when it is
// stopped. A start that is refused (the model file is not a GGUF, say) used
// to be dropped: the engine stayed stopped and the phone was told nothing.
// The answer now carries why in `refused` (additive: a phone that does not
// know the field ignores it), the same field a refused reload uses.
//
// The real facade and routes run on the real LLM provider and the real
// KoboldCpp service, whose start refuses a model that is not a GGUF before
// anything is spawned.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
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

class _Backend extends BackendManager {
  _Backend(super.storage, this.exe);
  final String exe;

  @override
  String? get backendPath => exe;
}

void main() {
  late AppDatabase db;
  late Router router;

  LocalModelInfo info(String path) => LocalModelInfo(
    path: path,
    filename: p.basename(path),
    sizeBytes: 36,
    modified: DateTime(2026),
  );

  /// The phone's backend routes over [provider], which knows [models].
  void routesOver(
    StorageService storage,
    LLMProvider provider,
    List<String> models,
  ) {
    db = AppDatabase.forTesting();
    router = Router();
    WebBackendRoutes(
      WebServerDeps(storage: storage, db: db, auth: AuthService(db)),
      router,
      backend: BackendFacade(
        provider,
        storage,
        FakeModelManager(localModels: [for (final m in models) info(m)]),
      ),
    );
  }

  Future<Map<String, dynamic>> post(
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final res = await router.call(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost$path'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode(body ?? {}),
      ),
    );
    expect(res.statusCode, 200);
    return jsonDecode(await res.readAsString()) as Map<String, dynamic>;
  }

  group('with the real start, which refuses a model that is not a GGUF', () {
    late Directory root;
    late StorageService storage;
    late KoboldService kobold;
    late LLMProvider provider;
    late String broken;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      HttpOverrides.global = null;
      root = Directory.systemTemp.createTempSync('fpai refused start');
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            return call.method == 'getApplicationDocumentsDirectory'
                ? root.path
                : null;
          });
      SharedPreferences.setMockInitialValues({});
      storage = StorageService();
      await storage.initialized;
      await storage.backendSettings.setBackendType('kobold');
      await storage.binDir.create(recursive: true);
      // Not a GGUF: the start refuses it before anything is spawned.
      broken = (File(
        p.join(root.path, 'broken.gguf'),
      )..writeAsBytesSync('XXXX'.codeUnits + List.filled(32, 0))).path;
      await storage.backendSettings.setLastUsedModelPath(broken);
      kobold = KoboldService(storage);
      provider = LLMProvider(
        kobold,
        OpenRouterService(apiUrl: '', apiKey: '', modelName: ''),
        storage,
        _Backend(storage, p.join(storage.binDir.path, 'koboldcpp')),
      );
      routesOver(storage, provider, [broken]);
    });

    tearDown(() async {
      provider.dispose();
      kobold.dispose();
      await db.close();
      root.deleteSync(recursive: true);
    });

    test('Restart with KoboldCpp stopped and a model that cannot be read: '
        'the answer says why nothing started', () async {
      final body = await post('/api/backend/restart');

      expect(body['refused'], contains('Not a valid GGUF'));
      expect(body['running'], isFalse);
      expect(
        body.containsKey('phase'),
        isTrue,
        reason: 'the status is as before',
      );
    });

    test('a model switch with KoboldCpp stopped, to a model that cannot be '
        'read: the answer says why nothing started', () async {
      final body = await post('/api/backend/models/switch', {'path': broken});

      expect(body['refused'], contains('Not a valid GGUF'));
      expect(body['running'], isFalse);
    });
  });

  group('with a start that goes ahead', () {
    late Directory root;
    late KoboldRig rig;

    setUp(() async {
      root = Directory.systemTemp.createTempSync('fpai started');
      rig = await KoboldRig.start(root);
      await rig.storage.backendSettings.setLastUsedModelPath(
        rig.gguf('m.gguf'),
      );
      routesOver(rig.storage, rig.provider, [rig.gguf('m.gguf')]);
    });

    tearDown(() async {
      await rig.close();
      await db.close();
      root.deleteSync(recursive: true);
    });

    test('Restart has no refusal to say', () async {
      final body = await post('/api/backend/restart');

      expect(body.containsKey('refused'), isTrue);
      expect(body['refused'], isNull);
      expect(rig.kobold.launches, 1);
    });
  });
}
