// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A reload is checked against what KoboldCpp says it loaded. KoboldCpp
// 1.122.1 answers a reload whose config fails to load (out of memory, a bad
// vision file, a missing model) by relaunching the config it was started
// with, and says nothing: the app used to record the new config as loaded
// and hold prompts to its context while the engine ran the old one.
//
// The engine here is a real HTTP server on loopback with those semantics.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/services.dart';

/// KoboldCpp's admin, model and context routes, and a chat completion that
/// generates. A reload is answered at once and acted on half a second later
/// by a new model process; one in [failing] does not load, and the engine
/// goes back to the config it was started with.
class _Engine {
  _Engine._(this._server, this.adminDir);

  static Future<_Engine> start(String adminDir) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _Engine._(server, adminDir).._serve();
  }

  final HttpServer _server;
  final String adminDir;
  final failing = <String>{};
  final reloads = <String>[];
  String model = 'koboldcpp/old-model';
  int context = 16384;

  /// What it runs for a config with no contextsize: 16,384 on 1.122.1,
  /// 12,288 on 1.117.1.
  int defaultContext = 16384;
  DateTime _started = DateTime.now();

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  Future<void> close() => _server.close(force: true);

  void _serve() => _server.listen((r) async {
    final body = switch (r.uri.path) {
      '/api/admin/reload_config' => await _reload(r),
      '/api/extra/perf' => {
        'uptime': DateTime.now().difference(_started).inMilliseconds / 1000,
      },
      '/api/v1/model' => {'result': model},
      '/api/extra/true_max_context_length' => {'value': context},
      '/v1/chat/completions' => {
        'choices': [
          {
            'message': {'role': 'assistant', 'content': 'Ready.'},
            'finish_reason': 'length',
          },
        ],
        'usage': {'completion_tokens': 2},
      },
      _ => null,
    };
    r.response
      ..statusCode = body == null ? 404 : 200
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body ?? {'error': 'not found'}));
    await r.response.close();
  });

  Future<Map<String, dynamic>> _reload(HttpRequest r) async {
    final name =
        (jsonDecode(await utf8.decodeStream(r)) as Map)['filename'] as String;
    reloads.add(name);
    Timer(const Duration(milliseconds: 500), () {
      _started = DateTime.now();
      if (failing.contains(name)) return;
      final config =
          jsonDecode(File(p.join(adminDir, name)).readAsStringSync()) as Map;
      final file = config['model_param']?.toString() ?? '';
      model = 'koboldcpp/${p.basenameWithoutExtension(file)}';
      context = (config['contextsize'] as num?)?.toInt() ?? defaultContext;
    });
    return {'success': true};
  }
}

class _Backend extends BackendManager {
  _Backend(super.storage, this.exe);
  final String exe;

  @override
  String? get backendPath => exe;
}

/// The app's KoboldCpp service with the process left out: whether it runs,
/// and the stop and start the chat fallback asks for, are recorded.
class _Kobold extends KoboldService {
  _Kobold(super.storage);

  bool running = true;
  int stops = 0;
  int launches = 0;

  @override
  Future<void> reconnectIfAlive() async {}

  @override
  bool get isRunning => running;

  @override
  bool get isProcessRunning => running;

  @override
  Future<void> stopKobold() async {
    stops++;
    running = false;
  }

  @override
  Future<KoboldLaunchResult> launch(
    String executablePath, {
    String? pickedModel,
    int port = 5001,
  }) async {
    launches++;
    running = true;
    return const KoboldLaunchResult.started();
  }
}

void main() {
  late Directory root;
  late StorageService storage;
  late _Engine engine;
  late _Kobold kobold;
  late LLMProvider provider;
  late String newModel;

  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
    root = await Directory.systemTemp.createTemp('fpai reload check');
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
    newModel = p.join(root.path, 'new-model.gguf');
    File(newModel).writeAsBytesSync('GGUF'.codeUnits + List.filled(32, 0));
    await storage.backendSettings.setLastUsedModelPath(newModel);

    final adminDir = koboldAdminDirFor(storage);
    await Directory(adminDir).create(recursive: true);
    engine = await _Engine.start(adminDir);
    kobold = _Kobold(storage)..setBaseUrl(engine.baseUrl);
    final exe = p.join(storage.binDir.path, 'koboldcpp');
    provider = LLMProvider(
      kobold,
      OpenRouterService(apiUrl: '', apiKey: '', modelName: ''),
      storage,
      _Backend(storage, exe),
    );
  });

  tearDown(() async {
    provider.dispose();
    await engine.close();
    await root.delete(recursive: true);
  });

  /// Chat's preset, written in the engine folder and chosen.
  Future<void> chatPreset(Map<String, dynamic> config) async {
    final file = File(p.join(storage.binDir.path, 'New.kcpps'))
      ..writeAsStringSync(jsonEncode(config));
    await storage.backendSettings.setActiveKcppsPath(file.path);
  }

  /// The chat config as staged for the engine, which is its key.
  String stagedChat() => File(
    p.join(koboldAdminDirFor(storage), kStagedChatConfig),
  ).readAsStringSync();

  test(
    'a chat preset KoboldCpp could not load: not recorded as loaded, '
    'prompts held to the context the engine runs, and a fresh start',
    () async {
      await chatPreset({'model_param': newModel, 'contextsize': 65536});
      engine.failing.add(kStagedChatConfig);

      await provider.reloadChatKobold();

      expect(engine.reloads, [kStagedChatConfig]);
      expect(engine.model, 'koboldcpp/old-model');
      expect(kobold.isResident(stagedChat()), isFalse);
      expect(storage.backendSettings.engineContextSize, 16384);
      expect(storage.backendSettings.promptContext(65536), 16384);
      expect(kobold.stops, 1, reason: 'the reload failed, so chat restarts');
      expect(kobold.launches, 1);
      expect(kobold.logs.join('\n'), contains('could not load new-model.gguf'));
    },
  );

  test('a chat preset that loads is recorded, with the engine\'s context; '
      'no restart', () async {
    await chatPreset({'model_param': newModel, 'contextsize': 65536});

    await provider.reloadChatKobold();

    expect(engine.model, 'koboldcpp/new-model');
    expect(kobold.isResident(stagedChat()), isTrue);
    expect(storage.backendSettings.engineContextSize, 65536);
    expect(kobold.stops, 0);
    expect(kobold.launches, 0);
  });

  test('a preset with no context on an engine whose own default is not '
      '16,384 loads, and prompts are held to what it runs', () async {
    engine.defaultContext = 12288;
    await chatPreset({'model_param': newModel});

    await provider.reloadChatKobold();

    expect(kobold.stops, 0, reason: 'nothing failed, so nothing restarts');
    expect(kobold.isResident(stagedChat()), isTrue);
    expect(storage.backendSettings.engineContextSize, 12288);
  });

  test('a preset with no context: prompts are held to the 16,384 KoboldCpp '
      'runs', () async {
    await chatPreset({'model_param': newModel});

    await provider.reloadChatKobold();

    expect(engine.model, 'koboldcpp/new-model');
    expect(kobold.isResident(stagedChat()), isTrue);
    expect(storage.backendSettings.engineContextSize, 16384);
    expect(storage.backendSettings.promptContext(32768), 16384);
  });

  test('a trial KoboldCpp could not load is not a trial that ran', () async {
    engine.failing.add('fpai-trial.kcpps');
    final config = {'model_param': newModel, 'contextsize': 8192};

    final ran = await provider.loadKoboldTrial('fpai-trial.kcpps', config);

    expect(ran, isFalse);
    expect(engine.reloads, ['fpai-trial.kcpps']);
    expect(kobold.isResident(encodeKcpps(config)), isFalse);
    expect(storage.backendSettings.engineContextSize, 16384);
  });

  test('restore() of a config KoboldCpp could not load throws, and nothing '
      'is recorded as loaded', () async {
    final config = {'model_param': newModel, 'contextsize': 65536};
    final json = encodeKcpps(config);
    final file = await stageKoboldConfig(
      engine.adminDir,
      'fpai-worker.kcpps',
      json,
    );
    engine.failing.add('fpai-worker.kcpps');
    String? resident;
    int? context;
    var forgot = false;
    final host = KoboldProcessHost(
      baseUrl: engine.baseUrl,
      stageConfig: () async => KoboldStagedRole(
        filename: 'fpai-worker.kcpps',
        path: file.path,
        key: json,
        modelPath: newModel,
        kcppsPath: '',
        expectedModel: koboldExpectedModelName(config),
        contextSize: koboldExpectedContext(config),
      ),
      noteResident: (key) => resident = key,
      onEngineContext: (c) => context = c,
      forgetLoadedPair: () => forgot = true,
      waitForReload: () => waitForKoboldReload(
        uptime: () => koboldEngineUptime(engine.baseUrl),
        ready: () => probeKoboldGenerationReady(baseUrl: engine.baseUrl),
        timeout: const Duration(seconds: 10),
      ),
      isProcessRunning: () => true,
      stopProcess: () async {},
      startProcess: () async {},
      admin: HttpGpuSwapHost(
        kind: LocalSwapKind.koboldProcess,
        apiUrl: engine.baseUrl,
        modelId: newModel,
      ),
    );

    await expectLater(host.restore(), throwsA(isA<KoboldSwapFailed>()));
    expect(resident, isNot(json));
    expect(context, 16384);
    expect(forgot, isTrue);
  });

  test('a trial that loads ran', () async {
    final config = {'model_param': newModel, 'contextsize': 8192};

    expect(await provider.loadKoboldTrial('fpai-trial.kcpps', config), isTrue);
    expect(engine.context, 8192);
  });
}
