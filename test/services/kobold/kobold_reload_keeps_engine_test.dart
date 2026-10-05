// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A live reload of chat's config that KoboldCpp could not load. KoboldCpp
// answers one by going back to the model it was running, which still works.
// The app used to stop that engine and start a fresh one; when the fresh
// start was refused (the new model file is not a GGUF, say) nothing ran any
// more and no reason was shown.
//
// Now the app decides first whether a fresh start could run. If it could
// not, nothing is stopped: the old model keeps running and the caller gets a
// refusal that says the new model was not loaded, that the previous one is
// still running, and why. If it could, the reason is noted, the engine is
// stopped and started, and the start's result is what the caller gets (the
// existing readable-model case, which restarts, is in
// kobold_reload_check_test).
//
// The engine is a real HTTP server on loopback with KoboldCpp 1.122.1's
// semantics (see loopback_kobold.dart). The start goes through the REAL
// KoboldService.launch, whose model check refuses a file that is not a
// GGUF; only whether a process runs, and the stop, are faked.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/services.dart';

import 'loopback_kobold.dart';

class _Backend extends BackendManager {
  _Backend(super.storage, this.exe);
  final String exe;

  @override
  String? get backendPath => exe;
}

/// The app's KoboldCpp with no process: running, stops and starts are
/// recorded. [launch] is not replaced: the real start decides, and refuses.
class _Kobold extends KoboldService {
  _Kobold(super.storage);

  bool running = true;
  int stops = 0;
  int starts = 0;

  /// What the log said when the engine was stopped.
  String? logAtStop;

  @override
  Future<void> reconnectIfAlive() async {}

  @override
  bool get isRunning => running;

  @override
  bool get isProcessRunning => running;

  @override
  Future<void> stopKobold() async {
    stops++;
    logAtStop = logs.join('\n');
    running = false;
  }

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
    return super.startKobold(
      executablePath,
      modelPath,
      kcppsPath: kcppsPath,
      mmprojPath: mmprojPath,
      port: port,
      gpuLayers: gpuLayers,
      contextSize: contextSize,
      useVulkan: useVulkan,
      useCublas: useCublas,
      useMetal: useMetal,
      useRocm: useRocm,
    );
  }
}

void main() {
  late Directory root;
  late StorageService storage;
  late LoopbackKobold engine;
  late _Kobold kobold;
  late LLMProvider provider;
  late String newModel;

  setUpAll(() => HttpOverrides.global = null);

  /// The app's pieces on a fresh storage; returns the folder configs are
  /// staged in. The engine is the caller's to start and point [kobold] at.
  Future<String> rig() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
    root = await Directory.systemTemp.createTemp('fpai reload keeps');
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
    kobold = _Kobold(storage);
    provider = LLMProvider(
      kobold,
      OpenRouterService(apiUrl: '', apiKey: '', modelName: ''),
      storage,
      _Backend(storage, p.join(storage.binDir.path, 'koboldcpp')),
    );
    return adminDir;
  }

  tearDown(() async {
    provider.dispose();
    await root.delete(recursive: true);
  });

  /// The reload's answer, typed loosely so this compiles before the answer
  /// existed (void) and after it (KoboldLaunchResult?).
  Future<dynamic> reload() => provider.reloadChatKobold() as Future<dynamic>;

  group('on KoboldCpp 1.122.1 going back to the old model', () {
    setUp(() async {
      engine = await LoopbackKobold.start(await rig());
      kobold.setBaseUrl(engine.baseUrl);
    });

    tearDown(() => engine.close());

    test('a new model a fresh start would refuse: the old model keeps '
        'running, and the caller is told why', () async {
      // Not a GGUF: the model check refuses it, so a restart cannot run.
      File(newModel).writeAsBytesSync('XXXX'.codeUnits + List.filled(32, 0));
      engine.failing.add(kStagedChatConfig);

      final dynamic result = await reload();

      expect(engine.reloads, [kStagedChatConfig]);
      expect(
        engine.model,
        'koboldcpp/startup-model',
        reason: 'KoboldCpp went back to the old model, which still works',
      );
      printOnFailure(
        'starts=${kobold.starts} running=${kobold.running} '
        'logs=${kobold.logs.join(' | ')}',
      );
      expect(
        kobold.stops,
        0,
        reason:
            'BUG M1: the working engine was stopped although the fresh '
            'start was always going to be refused',
      );
      expect(kobold.starts, 0);
      expect(kobold.running, isTrue);
      expect(
        result,
        isA<KoboldLaunchResult>(),
        reason: 'BUG M1: the refusal was dropped',
      );
      expect((result as KoboldLaunchResult).started, isFalse);
      expect(
        result.message,
        allOf(
          contains('The new model was not loaded'),
          contains('The previous one is still running'),
          contains('Not a valid GGUF'),
        ),
      );
      // Said where the status line and the engine log keep it, with no stop
      // to clear it.
      expect(kobold.modelLoadingStatus, contains('could not load new-model'));
      expect(kobold.logs.join('\n'), contains('could not load new-model'));
    });

    test('a chat preset that asks KoboldCpp to run a program is refused at '
        'the reload: nothing is sent or stopped, and the refusal comes '
        'back', () async {
      File(p.join(storage.binDir.path, 'Theirs.kcpps')).writeAsStringSync(
        jsonEncode({
          'model_param': newModel,
          'contextsize': 8192,
          'mcpfile': 'https://example.com/servers.json',
        }),
      );
      await storage.backendSettings.setActiveKcppsPath(
        p.join(storage.binDir.path, 'Theirs.kcpps'),
      );

      final dynamic result = await reload();

      expect(engine.reloads, isEmpty, reason: 'KoboldCpp was never asked');
      expect(kobold.stops, 0);
      expect(kobold.starts, 0);
      expect(kobold.running, isTrue);
      expect(result, isA<KoboldLaunchResult>());
      expect((result as KoboldLaunchResult).started, isFalse);
      expect(
        result.message,
        allOf(
          contains('The previous one is still running'),
          contains('mcpfile'),
          contains('pick another preset'),
        ),
      );
      expect(kobold.modelLoadingStatus, contains('mcpfile'));
    });

    test('a new model a fresh start can run: the reason is noted first, the '
        'engine is stopped and started, and the start\'s answer comes '
        'back', () async {
      // Readable, so a restart can run. There is no engine program here, so
      // the real start is refused after the stop.
      engine.failing.add(kStagedChatConfig);

      final dynamic result = await reload();

      expect(kobold.stops, 1);
      expect(kobold.starts, 1);
      expect(
        kobold.logAtStop,
        contains('could not load new-model'),
        reason: 'noted before the stop, which clears the status line',
      );
      expect(result, isA<KoboldLaunchResult>());
      expect((result as KoboldLaunchResult).started, isFalse);
      expect(result.message, contains('could not be started'));
      expect(result.message, isNot(contains('still running')));
    });

    test('a reload that loads says nothing', () async {
      final dynamic result = await reload();

      expect(engine.model, 'koboldcpp/new-model');
      expect(result, isNull);
      expect(kobold.stops, 0);
    });
  });

  group('when the swap\'s own last resort already stopped the engine', () {
    late HttpServer admin404;

    setUp(() async {
      // An engine that has no admin to reload: the swap restarts it.
      admin404 = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      admin404.listen((r) async {
        r.response.statusCode = 404;
        await r.response.close();
      });
      await rig();
      kobold.setBaseUrl('http://127.0.0.1:${admin404.port}');
    });

    tearDown(() => admin404.close(force: true));

    test('the refusal of that restart comes back as it is: the previous '
        'model is not claimed to run, and nothing starts it again', () async {
      File(newModel).writeAsBytesSync('XXXX'.codeUnits + List.filled(32, 0));

      final dynamic result = await reload();

      expect(kobold.stops, 1, reason: 'the swap stopped it for a restart');
      expect(kobold.starts, 1, reason: 'that restart was refused, once');
      expect(kobold.running, isFalse);
      expect(result, isA<KoboldLaunchResult>());
      expect((result as KoboldLaunchResult).started, isFalse);
      expect(result.message, contains('Not a valid GGUF'));
      expect(result.message, isNot(contains('still running')));
    });
  });
}
