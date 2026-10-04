// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Model swaps on a REAL KoboldCpp, through the app's own provider: a story
// job's model is loaded over the chat model and the chat model put back.
// What the engine really has loaded is read from the engine each time (the
// two configs differ in context size). Skipped unless KOBOLD_LIVE_BIN and
// KOBOLD_LIVE_MODEL are set; see kobold_engine_live_test.dart.
//
// The swap test that used to live in kobold_engine_live_test.dart moved
// here. It needed a wrapper that waited for the engine between an unload
// and a load, because the app sent the two back to back and the engine
// drops a request that arrives while it is acting on another. The app now
// sends one request per swap and waits for it itself, so the wrapper is
// gone and the tests below run the app's own hosts unaided.

@Tags(['kobold_live'])
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'live_engine.dart';

const _slow = Timeout(Duration(minutes: 10));

class _Engine extends BackendManager {
  _Engine(super.storage, this.exe);
  final String exe;

  @override
  String? get backendPath => exe;
}

void main() {
  late Directory root;
  late StorageService storage;
  late KoboldService kobold;
  late LLMProvider provider;
  late String exe;
  late int port;

  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    final temp = await Directory.systemTemp.createTemp('fpai swap live');
    root = Directory(temp.resolveSymbolicLinksSync());
    TestWidgetsFlutterBinding.ensureInitialized();
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
    final b = storage.backendSettings;
    await b.setBackendType('kobold');
    await b.setContextSize(4096);
    await b.setLastUsedModelPath(liveEngineModel);

    kobold = KoboldService(storage);
    exe = await copyEngineInto(storage.binDir);
    port = await freePort();
    kobold.setBaseUrl('http://127.0.0.1:$port');
    provider = LLMProvider(
      kobold,
      OpenRouterService(apiUrl: '', apiKey: '', modelName: ''),
      storage,
      _Engine(storage, exe),
    );

    // Chat is up first, the way a story job finds it.
    expect((await kobold.launch(exe, port: port)).started, isTrue);
    await waitForLiveModel(port);
    for (var i = 0; i < 120 && !kobold.modelReady; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    expect(kobold.modelReady, isTrue);
    expect(await liveContextSize(port), 4096);
  });

  tearDown(() async {
    await kobold.stopKobold();
    provider.dispose();
    await stopLiveEnginesUnder(root);
    await root.delete(recursive: true);
  });

  /// A story job on the same model with its own preset (a 2048 context).
  LaneHost job() {
    final preset = File(p.join(storage.binDir.path, 'job.kcpps'))
      ..writeAsStringSync('{"contextsize": 2048, "noswa": true}');
    return provider.laneHost(
      type: 'kobold',
      url: '',
      model: liveEngineModel,
      kcpps: preset.path,
    )!;
  }

  Future<int?> context() => liveContextSize(port);

  test(
    'a job\'s call runs on the job\'s config, a second call reloads nothing, '
    'and the chat model is put back afterwards',
    () async {
      final lane = job();
      final said = <String>{};
      kobold.addListener(() => said.add(kobold.modelLoadingStatus));

      expect(await lane.hold(context), 2048);
      expect(
        said,
        contains('Loading ${p.basename(liveEngineModel)} for the story...'),
        reason: 'the status line says which model is loading and why',
      );

      // Still the job's turn: the engine must not be reloaded again.
      final before = await liveUptime(port);
      expect(await lane.hold(context), 2048);
      expect(await liveUptime(port), greaterThan(before!));

      await lane.restore();
      expect(await context(), 4096);
      expect(
        said,
        contains('Loading ${p.basename(liveEngineModel)} for chat...'),
      );
      // A swap loads; the status line never says it is unloading.
      expect(said, isNot(contains('Unloading model...')));
      // No link was made for the swap: only staged configs are in the
      // admin folder.
      final staged = Directory(koboldAdminDirFor(storage)).listSync();
      expect(staged.whereType<Link>(), isEmpty);
      expect(
        staged.map((f) => p.basename(f.path)),
        everyElement(startsWith(kStagedConfigPrefix)),
      );
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );

  test(
    'swapping back and forth six times never leaves the wrong config '
    'loaded',
    () async {
      final lane = job();
      for (var round = 1; round <= 6; round++) {
        expect(await lane.hold(context), 2048, reason: 'job, round $round');
        await lane.restore();
        expect(await context(), 4096, reason: 'chat, round $round');
      }
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );

  test(
    'a job set to the chat model\'s own model and preset reloads nothing',
    () async {
      final lane = provider.laneHost(
        type: 'kobold',
        url: '',
        model: liveEngineModel,
      )!;

      final before = await liveUptime(port);
      expect(await lane.hold(context), 4096);
      await lane.restore();
      expect(await liveUptime(port), greaterThan(before!));
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );

  test(
    'when putting chat back has to start the engine again, it starts the '
    'chat model Settings names now',
    () async {
      final lane = job();
      expect(await lane.hold(context), 2048);

      // Settings now names another chat model: the same file under another
      // name, so the engine's answer shows which one was started.
      final now = Link(p.join(root.path, 'chat-now.gguf'))
        ..createSync(liveEngineModel);
      await storage.backendSettings.setLastUsedModelPath(now.path);

      // The engine goes away behind the app's back, so chat cannot come
      // back by a reload: the engine has to be started.
      await stopLiveEnginesUnder(root);
      await lane.restore();
      await waitForLiveModel(port);

      expect(await liveLoadedModel(port), contains('chat-now'));
      expect(await context(), 4096);
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );

  test(
    'when the engine is restarted behind a job\'s back, its next call puts '
    'its own config back',
    () async {
      final lane = job();
      expect(await lane.hold(context), 2048);

      // Outside the job: the engine is started again with the chat model
      // (what Settings, or a crash and restart, does).
      await kobold.stopKobold();
      expect((await kobold.launch(exe, port: port)).started, isTrue);
      await waitForLiveModel(port);
      expect(await context(), 4096);

      expect(await lane.hold(context), 2048);
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );
}
