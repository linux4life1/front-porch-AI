// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The user's own chat length comes back (maintainer ruling I, 2026-10-05).
// Choosing a preset copies its context in as the context in use, which is
// what the prompt budget, the cards and the phone read. Before, nothing put
// the user's own back: after trying a 32k preset and going back to automatic
// (or picking a model with no preset of its own), KoboldCpp launched at 32k,
// or at a small preset's 8k, under the 16k floor. Now the user's own context
// is kept when a preset is first chosen and comes back when it goes; going
// from one preset to another keeps it. Every pick, on the desktop and on the
// phone, comes through the same place.
//
// Real preset files and a real preferences store.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/storage/settings/backend_settings.dart';
import 'package:front_porch_ai/services/storage_service.dart';

import '../kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('fpai own context'));
  tearDown(() => dir.deleteSync(recursive: true));

  String preset(String name, int context) => (File(
    p.join(dir.path, name),
  )..writeAsStringSync(jsonEncode({'contextsize': context}))).path;

  group('the settings', () {
    late BackendSettings s;

    /// Settings over a real preferences store, as the app starts them.
    Future<BackendSettings> open() async => BackendSettings()
      ..initializeBase(await SharedPreferences.getInstance(), () {})
      ..load();

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      s = await open();
      await s.setBackendType('kobold');
      await s.setContextSize(16384);
    });

    test('a preset sets the context while it is chosen, and the user\'s own '
        'comes back when it is cleared', () async {
      await s.setActiveKcppsPath(preset('Long chats.kcpps', 32768));
      expect(s.contextSize, 32768, reason: 'the preset\'s, in use');

      await s.setActiveKcppsPath(null);

      expect(s.contextSize, 16384);
    });

    test('from one preset to another, the user\'s own is kept', () async {
      await s.setActiveKcppsPath(preset('Long chats.kcpps', 32768));
      await s.setActiveKcppsPath(preset('Small.kcpps', 8192));
      expect(s.contextSize, 8192);

      await s.setActiveKcppsPath(null);

      expect(s.contextSize, 16384, reason: 'not the first preset\'s');
    });

    test('it is kept across a restart of the app', () async {
      await s.setActiveKcppsPath(preset('Long chats.kcpps', 32768));

      final again = await open();
      expect(again.contextSize, 32768);
      await again.setActiveKcppsPath(null);

      expect(again.contextSize, 16384);
    });

    test('the context the phone sends back with every save does not take '
        'its place, on KoboldCpp or with the preset left on another '
        'backend', () async {
      for (final backend in ['kobold', 'openRouter']) {
        await s.setActiveKcppsPath(preset('Long chats.kcpps', 32768));
        await s.setBackendType(backend);
        await s.setContextSize(32768);
        await s.setBackendType('kobold');

        await s.setActiveKcppsPath(null);

        expect(s.contextSize, 16384, reason: backend);
      }
    });

    test('a context the user sets while a preset is left chosen on another '
        'backend is their own, and is what comes back', () async {
      await s.setActiveKcppsPath(preset('Long chats.kcpps', 32768));
      await s.setBackendType('openRouter');
      await s.setContextSize(24576);
      await s.setBackendType('kobold');

      await s.setActiveKcppsPath(null);

      expect(s.contextSize, 24576);
    });

    test('a different context set while a preset is chosen is the user\'s '
        'latest own (every screen locks it on KoboldCpp)', () async {
      await s.setActiveKcppsPath(preset('Long chats.kcpps', 32768));
      await s.setContextSize(24576);

      await s.setActiveKcppsPath(null);

      expect(s.contextSize, 24576);
    });

    test('with no preset the context is simply the user\'s', () async {
      await s.setActiveKcppsPath(null);
      expect(s.contextSize, 16384);
      await s.setContextSize(20480);
      await s.setActiveKcppsPath(null);

      expect(s.contextSize, 20480);
    });
  });

  group('every pick goes through it', () {
    late StorageService storage;
    late String withPreset;
    late String without;

    setUp(() async {
      storage = await createStorageService();
      await storage.backendSettings.setBackendType('kobold');
      await storage.backendSettings.setContextSize(16384);
      withPreset = p.join(dir.path, 'A.gguf');
      without = p.join(dir.path, 'B.gguf');
      for (final m in [withPreset, without]) {
        File(m).writeAsBytesSync([...'GGUF'.codeUnits, 3, 0, 0, 0]);
      }
      await storage.backendSettings.setLastUsedModelPath(withPreset);
    });

    test('choosing a preset and then none, as Settings and the phone '
        'do', () async {
      await chooseKoboldPreset(storage, preset('Long chats.kcpps', 32768));
      expect(storage.backendSettings.contextSize, 32768);

      await chooseKoboldPreset(storage, null);

      expect(storage.backendSettings.contextSize, 16384);
    });

    test('picking a model that has no preset of its own', () async {
      await chooseKoboldPreset(storage, preset('Long chats.kcpps', 32768));

      await selectKoboldModel(storage, without);

      expect(storage.backendSettings.activeKcppsPath, isNull);
      expect(storage.backendSettings.contextSize, 16384);
    });

    test('picking a model whose preset is another one keeps the user\'s '
        'own for later', () async {
      await chooseKoboldPreset(storage, preset('Long chats.kcpps', 32768));
      await storage.presetSettings.setModelPreset(
        without,
        preset('Small.kcpps', 8192),
      );

      await selectKoboldModel(storage, without);
      expect(storage.backendSettings.contextSize, 8192);
      await chooseKoboldPreset(storage, null);

      expect(storage.backendSettings.contextSize, 16384);
    });
  });
}
