// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Why KoboldCpp stopped reaches the phone in the field it already reads for
// the status line, `statusMessage`, on /api/backend/status (the Local
// backend card) and /api/backend/local-model (the Local model card). No new
// field: an older phone shows it where it showed the loading steps.
//
// The real routes, facade, LLM provider and KoboldCpp service run; the
// "engine" is a shell script that prints KoboldCpp's out-of-memory line and
// exits, so a real process stops on its own. POSIX only.

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
import 'package:front_porch_ai/utils/utils.dart';

import '../../golden/support/fakes_services.dart';

class _Backend extends BackendManager {
  _Backend(super.storage, this.exe);
  final String exe;

  @override
  String? get backendPath => exe;
}

/// The model here is four bytes of header: there is nothing more to read.
class _Models extends FakeModelManager {
  _Models(String model)
    : super(
        localModels: [
          LocalModelInfo(
            path: model,
            filename: p.basename(model),
            sizeBytes: 8,
            modified: DateTime(2026),
          ),
        ],
      );

  @override
  Future<GGUFModelInfo?> getModelArchitectureInfo(String filePath) async =>
      null;
}

void main() {
  late Directory root;
  late StorageService storage;
  late KoboldService kobold;
  late LLMProvider provider;
  late AppDatabase db;
  late Router router;
  late String engine;
  late String model;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
    root = Directory.systemTemp.createTempSync('fpai stop reason phone');
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
    engine = p.join(root.path, 'koboldcpp-dies');
    File(engine).writeAsStringSync(
      '#!/bin/sh\n'
      "echo 'ggml_backend_cuda_buffer_type_alloc_buffer: allocating 9000.00 "
      "MiB on device 0: cudaMalloc failed: out of memory'\n"
      'sleep 0.5\n'
      'exit 1\n',
    );
    await Process.run('chmod', ['755', engine]);
    model = p.join(root.path, 'model.gguf');
    File(model).writeAsBytesSync([...'GGUF'.codeUnits, 3, 0, 0, 0]);
    await storage.backendSettings.setLastUsedModelPath(model);
    kobold = KoboldService(storage);
    provider = LLMProvider(
      kobold,
      OpenRouterService(apiUrl: '', apiKey: '', modelName: ''),
      storage,
      _Backend(storage, engine),
    );
    db = AppDatabase.forTesting();
    router = Router();
    WebBackendRoutes(
      WebServerDeps(storage: storage, db: db, auth: AuthService(db)),
      router,
      backend: BackendFacade(provider, storage, _Models(model)),
    );
  });

  tearDown(() async {
    await kobold.stopKobold();
    provider.dispose();
    kobold.dispose();
    await db.close();
    final left = await Process.run('pgrep', ['-f', RegExp.escape(engine)]);
    root.deleteSync(recursive: true);
    expect((left.stdout as String).trim(), isEmpty, reason: 'nothing left');
  });

  Future<Map<String, dynamic>> get(String path) async {
    final res = await router.call(
      shelf.Request('GET', Uri.parse('http://localhost$path')),
    );
    expect(res.statusCode, 200);
    return jsonDecode(await res.readAsString()) as Map<String, dynamic>;
  }

  test('after KoboldCpp stops on its own, both cards are told why in the '
      'status line they already show', () async {
    expect(
      (await kobold.startKobold(engine, model, port: 5994)).started,
      isTrue,
    );
    for (
      var i = 0;
      i < 300 && (kobold.isRunning || kobold.lastFailure == null);
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    printOnFailure('logs:\n${kobold.logs.join('\n')}');
    final why = kobold.lastFailure!.message;
    expect(why, contains('ran out of graphics memory'));

    final status = await get('/api/backend/status');
    expect(status['running'], isFalse);
    expect(status['phase'], 'stopped');
    expect(status['statusMessage'], why);

    final card = await get('/api/backend/local-model');
    expect(card['phase'], 'stopped');
    expect(card['statusMessage'], why);
  }, skip: Platform.isWindows ? 'the engine here is a shell script' : false);
}
