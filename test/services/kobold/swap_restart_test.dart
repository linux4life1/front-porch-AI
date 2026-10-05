// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The last resort of a swap is a restart of the engine. Three things about
// it:
// - an engine known not to run is not asked to reload first (the admin call
//   cannot be answered, and its retries took ten seconds to run out);
// - a restart that is refused (the model file cannot be read, no model is
//   chosen) fails the swap at once, in the refusal's words, instead of
//   waiting for an engine that was never started for as long as a model takes
//   to load, with the swap lock held;
// - whether a reload the engine never acted on is restarted or reported is
//   decided by the kind of failure it is, not by the words in its message.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/services.dart';

HttpGpuSwapHost _admin(Future<http.Response> Function() send) =>
    HttpGpuSwapHost(
      kind: LocalSwapKind.koboldProcess,
      apiUrl: 'http://127.0.0.1:5001',
      modelId: '/tmp/model.gguf',
      send: (method, uri, headers, body) => send(),
    );

/// A reload the engine never acted on, whose message happens to read like a
/// blip on the connection.
class _WordyTimeout extends KoboldSwapTimeout {
  const _WordyTimeout() : super(restarted: false, waited: Duration.zero);

  @override
  String toString() => 'Connection refused: timed out waiting for the reload';
}

class _Backend extends BackendManager {
  _Backend(super.storage, this.exe);
  final String exe;

  @override
  String? get backendPath => exe;
}

/// The app's KoboldCpp service with no process, which refuses every start.
class _Refusing extends KoboldService {
  _Refusing(super.storage);

  int starts = 0;

  @override
  Future<void> reconnectIfAlive() async {}

  @override
  bool get isRunning => false;

  @override
  bool get isProcessRunning => false;

  @override
  Future<KoboldLaunchResult> startKobold(
    String executablePath,
    String modelPath, {
    String? kcppsPath,
    String? mmprojPath,
    int port = 5001,
    int gpuLayers = 0,
    int contextSize = 4096,
    bool useVulkan = false,
    bool useCublas = false,
    bool useMetal = false,
    bool useRocm = false,
  }) async {
    starts++;
    return const KoboldLaunchResult.refused('The model file cannot be read.');
  }
}

void main() {
  group('an engine known not to run', () {
    late int adminHits;
    late int starts;
    late int stops;
    late KoboldProcessHost host;

    setUp(() {
      adminHits = 0;
      starts = 0;
      stops = 0;
      host = KoboldProcessHost(
        baseUrl: 'http://127.0.0.1:5001',
        isProcessRunning: () => false,
        adminRetryDelay: Duration.zero,
        stopProcess: () async => stops++,
        startProcess: () async => starts++,
        admin: _admin(() async {
          adminHits++;
          throw Exception('Connection refused');
        }),
      );
    });

    test('is restarted without being asked to reload first', () async {
      await host.restore();

      expect(adminHits, 0, reason: 'nothing answers an admin call');
      expect(starts, 1);
    });

    test('is not asked to unload either', () async {
      await host.unload();

      expect(adminHits, 0);
      expect(stops, 1);
    });
  });

  test(
    'a reload never acted on is restarted, whatever its message says',
    () async {
      var starts = 0;
      var stops = 0;
      final host = KoboldProcessHost(
        baseUrl: 'http://127.0.0.1:5001',
        isProcessRunning: () => true,
        waitForReload: () async => throw const _WordyTimeout(),
        stopProcess: () async => stops++,
        startProcess: () async => starts++,
        admin: _admin(() async => http.Response('{"success":true}', 200)),
      );

      await host.restore();

      expect(stops, 1, reason: 'the engine that ignored the reload is stopped');
      expect(starts, 1);
    },
  );

  group('a swap whose restart is refused', () {
    late Directory root;
    late StorageService storage;
    late _Refusing kobold;
    late LLMProvider provider;
    late String laneModel;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      root = Directory.systemTemp.createTempSync('fpai swap restart');
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
      File(
        p.join(root.path, 'chat.gguf'),
      ).writeAsBytesSync([...'GGUF'.codeUnits, 0, 0]);
      await storage.backendSettings.setLastUsedModelPath(
        p.join(root.path, 'chat.gguf'),
      );
      laneModel = p.join(root.path, 'lane.gguf');
      File(laneModel).writeAsBytesSync([...'GGUF'.codeUnits, 0, 0]);
      // Nothing answers here: a wait for the engine would run to its limit.
      kobold = _Refusing(storage)..setBaseUrl('http://127.0.0.1:1');
      provider = LLMProvider(
        kobold,
        OpenRouterService(apiUrl: '', apiKey: '', modelName: ''),
        storage,
        _Backend(storage, p.join(root.path, 'koboldcpp')),
      );
    });

    tearDown(() {
      provider.dispose();
      root.deleteSync(recursive: true);
    });

    test('fails the job at once, with the refusal\'s words', () async {
      final lane = provider.laneHost(
        type: 'kobold',
        url: '',
        model: laneModel,
      )!;

      await expectLater(
        lane
            .hold(
              () async =>
                  fail('the job must not run on a model that did not load'),
            )
            // The wait it replaces is a minute at least.
            .timeout(const Duration(seconds: 5)),
        throwsA(
          isA<KoboldSwapFailed>().having(
            (e) => e.message,
            'message',
            'The model file cannot be read.',
          ),
        ),
      );
      expect(kobold.starts, greaterThanOrEqualTo(1));
    });
  });
}
