// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// An Intel Mac cannot run KoboldCpp. The desktop greys it out in its chat
// backend picker and in its Realism evals host bar (koboldEnabled:
// !isIntelMac), and the phone's Settings now does too. An older phone still
// offers it, and the settings API it saves through took the switch. Now that
// API refuses a save that would switch either one to KoboldCpp on an Intel
// Mac, in the desktop's sentence, and stores nothing from that save. A page
// that already has KoboldCpp sends it back with the rest of its form, which
// is not a switch: KoboldCpp is the app's first backend, so an Intel Mac
// that never changed it can still save everything else. Anywhere else the
// switch goes through as before.
//
// The real routes, facade, LLM provider and engine manager; only the machine
// is chosen (a Mac or not, and what its processor answers).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/facade/facades.dart';
import 'package:front_porch_ai/services/web/routes/routes.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';

/// What the phone's Settings page sends on Save: its whole form, as it read
/// it (SettingsPage.tsx, save()).
const _form = [
  'backend',
  'remoteApiUrl',
  'remoteModelName',
  'contextSize',
  'reasoningEnabled',
  'reasoningEffort',
  'generation',
  'systemPrompt',
  'bannedPhrases',
  'spellCheckLanguage',
  'workerBackend',
  'workerRemoteApiUrl',
  'workerRemoteModelName',
  'workerKoboldModelPath',
  'workerKoboldKcppsPath',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late AppDatabase db;
  late StorageService storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fpai intel mac save');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return call.method == 'getApplicationDocumentsDirectory'
              ? root.path
              : null;
        });
    // The engine manager's start-up update check stays off the network.
    SharedPreferences.setMockInitialValues({'update_auto_check': false});
    FlutterSecureStorage.setMockInitialValues({});
    storage = StorageService();
    await storage.initialized;
    await storage.backendSettings.setBackendType('openRouter');
    db = AppDatabase.forTesting();
  });

  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  /// The settings API on a machine that is a Mac or not, whose processor has
  /// answered [arch].
  Future<Router> api({bool mac = true, required String arch}) async {
    final engine = BackendManager(
      storage,
      onMac: mac,
      readArch: () async => arch,
    );
    await engine.architectureKnown;
    final kobold = KoboldService(storage);
    final llm = LLMProvider(
      kobold,
      OpenRouterService(apiUrl: '', apiKey: '', modelName: ''),
      storage,
      engine,
    );
    addTearDown(() {
      llm.dispose();
      kobold.dispose();
      engine.dispose();
    });
    final router = Router();
    WebSettingsRoutes(
      WebServerDeps(
        storage: storage,
        db: db,
        auth: AuthService(db),
        settingsFacade: SettingsFacade(storage, llm),
      ),
      router,
    );
    return router;
  }

  /// The phone opens Settings, changes [changes], and presses Save.
  Future<shelf.Response> save(
    Router api,
    Map<String, dynamic> Function(Map<String, dynamic> read) changes,
  ) async {
    final got = await api.call(
      shelf.Request('GET', Uri.parse('http://localhost/api/settings')),
    );
    expect(got.statusCode, 200);
    final read = jsonDecode(await got.readAsString()) as Map<String, dynamic>;
    return api.call(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost/api/settings'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          for (final key in _form) key: read[key],
          ...changes(read),
        }),
      ),
    );
  }

  /// The form's temperature, nudged: proof of whether the save was stored.
  Map<String, dynamic> warmer(Map<String, dynamic> read) => {
    ...(read['generation'] as Map<String, dynamic>),
    'temperature': storage.generationSettings.temperature + 0.25,
  };

  Future<Object?> error(shelf.Response res) async =>
      (jsonDecode(await res.readAsString()) as Map)['error'];

  test('on an Intel Mac a switch to KoboldCpp is refused in the desktop\'s '
      'words, and nothing in that save is stored', () async {
    final before = storage.generationSettings.temperature;
    final res = await save(
      await api(arch: 'x86_64'),
      (read) => {
        'backend': 'kobold',
        'remoteModelName': '',
        'generation': warmer(read),
      },
    );

    expect(res.statusCode, 400);
    expect(await error(res), kIntelMacLocalUnsupported);
    expect(storage.backendSettings.backendType, 'openRouter');
    expect(storage.generationSettings.temperature, before);
  });

  test('so is a switch of the Realism evals host to KoboldCpp', () async {
    final res = await save(
      await api(arch: 'x86_64'),
      (read) => {'workerBackend': 'kobold'},
    );

    expect(res.statusCode, 400);
    expect(await error(res), kIntelMacLocalUnsupported);
    expect(storage.workerBackendType, '');
  });

  test('KoboldCpp the Intel Mac already has, coming back with the form, is '
      'not a switch: the rest of the save is stored', () async {
    await storage.backendSettings.setBackendType('kobold');
    final before = storage.generationSettings.temperature;
    final res = await save(
      await api(arch: 'x86_64'),
      (read) => {'generation': warmer(read)},
    );

    expect(res.statusCode, 200);
    expect(storage.backendSettings.backendType, 'kobold');
    expect(
      storage.generationSettings.temperature,
      closeTo(before + 0.25, 1e-9),
    );
  });

  test('the same for a Realism evals host already on KoboldCpp', () async {
    await storage.setWorkerBackendType('kobold');
    final before = storage.generationSettings.temperature;
    final res = await save(
      await api(arch: 'x86_64'),
      (read) => {'generation': warmer(read)},
    );

    expect(res.statusCode, 200);
    expect(storage.workerBackendType, 'kobold');
    expect(
      storage.generationSettings.temperature,
      closeTo(before + 0.25, 1e-9),
    );
  });

  for (final (machine, mac, arch) in [
    ('Apple Silicon', true, 'arm64'),
    ('a Windows or Linux PC', false, 'x86_64'),
  ]) {
    test('on $machine a switch to KoboldCpp goes through as before', () async {
      final res = await save(
        await api(mac: mac, arch: arch),
        (read) => {'backend': 'kobold', 'remoteModelName': ''},
      );

      expect(res.statusCode, 200);
      expect(storage.backendSettings.backendType, 'kobold');
    });

    test('on $machine so does the Realism evals host', () async {
      final res = await save(
        await api(mac: mac, arch: arch),
        (read) => {'workerBackend': 'kobold'},
      );

      expect(res.statusCode, 200);
      expect(storage.workerBackendType, 'kobold');
    });
  }
}
