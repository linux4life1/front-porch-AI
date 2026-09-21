// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/settings_worker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _mockPathProvider() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_test_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;

  setUp(() async {
    _mockPathProvider();
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.initialized;
    await storage.backendSettings.setBackendType('kobold');
    await storage.backendSettings.setLastUsedModelPath('/models/mouth.gguf');
    await storage.setWorkerBackendType('kobold');
  });

  test('settings GET exposes the worker GGUF separately from mouth', () {
    final llm = LLMProvider(
      KoboldService(storage),
      OpenRouterService(),
      storage,
      BackendManager(storage),
    );
    addTearDown(llm.dispose);
    final snap = readWorkerSettings(storage, llm);
    expect(snap['workerKoboldModelPath'], '');
    expect(snap['workerKoboldKcppsPath'], '');
    expect(snap['lastUsedModelPath'], '/models/mouth.gguf');
  });

  test('settings POST empty worker GGUF inherits mouth', () async {
    await updateWorkerSettings(
      storage: storage,
      body: {'workerKoboldModelPath': '/models/worker.gguf'},
    );
    expect(storage.workerKoboldModelPath, '/models/worker.gguf');
    await updateWorkerSettings(
      storage: storage,
      body: {'workerKoboldModelPath': ''},
    );
    expect(storage.workerKoboldModelPath, isNull);
    expect(storage.resolvedWorkerKoboldModelPath(), '/models/mouth.gguf');
  });

  test('settings POST keeps worker .kcpps next to the worker GGUF', () async {
    await updateWorkerSettings(
      storage: storage,
      body: {
        'workerKoboldModelPath': '/models/worker.gguf',
        'workerKoboldKcppsPath': '/cfg/worker.kcpps',
      },
    );
    expect(storage.workerKoboldKcppsPath, '/cfg/worker.kcpps');
    expect(storage.resolvedWorkerKoboldKcppsPath(), '/cfg/worker.kcpps');
  });
}
