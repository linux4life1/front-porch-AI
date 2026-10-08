// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The "stop thinking" cap (`thinking_budget: 0` with thinking off, for a
// model whose template turns thinking on whatever it is asked) is decided
// by the model KoboldCpp has loaded. A helper or story model swapped in is
// judged by its own template, not by chat's. The requests go to a real
// HTTP server on loopback.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/services.dart';

/// The service without its start-up probe of port 5001.
class _Kobold extends KoboldService {
  _Kobold(super.storage);

  @override
  Future<void> reconnectIfAlive() async {}
}

void main() {
  late Directory root;
  late HttpServer server;
  late List<Map<String, dynamic>> bodies;
  late _Kobold kobold;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
    root = await Directory.systemTemp.createTemp('fpai thinking key');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return call.method == 'getApplicationDocumentsDirectory'
              ? root.path
              : null;
        });
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.initialized;
    await storage.backendSettings.setLastUsedModelPath('/m/chat.gguf');

    bodies = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      bodies.add(
        jsonDecode(await utf8.decodeStream(r)) as Map<String, dynamic>,
      );
      r.response
        ..headers.contentType = ContentType('text', 'event-stream')
        ..write(
          'data: {"choices":[{"delta":{"content":"ok"}}]}\n\n'
          'data: [DONE]\n\n',
        );
      await r.response.close();
    });
    kobold = _Kobold(storage)..setBaseUrl('http://127.0.0.1:${server.port}');
    kHardOnThinkingModels.clear();
  });

  tearDown(() async {
    kHardOnThinkingModels.clear();
    kobold.dispose();
    await server.close(force: true);
    await root.delete(recursive: true);
  });

  Future<Map<String, dynamic>> ask() async {
    await kobold
        .generateStream(GenerationParams(prompt: 'Rate this.'))
        .drain<void>();
    return bodies.single;
  }

  test('a helper model whose template forces thinking is capped while it '
      'is loaded', () async {
    kHardOnThinkingModels.add('/m/helper.gguf');
    kobold.noteAdminLoadedPair(modelPath: '/m/helper.gguf');

    expect((await ask())['thinking_budget'], 0);
  });

  test("chat's forced template does not cap a helper model that does not "
      'force it', () async {
    kHardOnThinkingModels.add('/m/chat.gguf');
    kobold.noteAdminLoadedPair(modelPath: '/m/helper.gguf');

    expect((await ask()).containsKey('thinking_budget'), isFalse);
  });

  test("with nothing recorded as loaded, chat's model decides", () async {
    kHardOnThinkingModels.add('/m/chat.gguf');

    expect((await ask())['thinking_budget'], 0);
  });

  test('the system-message check follows the loaded model too: a helper '
      "model is judged by its own template, not by chat's", () async {
    kobold.noteAdminLoadedPair(modelPath: '/m/helper.gguf');

    // The moment a model is ready arms the check for that model.
    kobold.debugMarkModelReady().ignore();

    expect(kobold.systemRoleIdentity, contains('/m/helper.gguf'));
    expect(kobold.systemRoleIdentity, isNot(contains('/m/chat.gguf')));
  });
}
