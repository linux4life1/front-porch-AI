// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The app's KoboldCpp handling against a REAL KoboldCpp. Nothing here is
// stubbed: a real engine is started, asked what it has loaded, and stopped.
// Skipped unless both are set (CI has no engine or model):
//
//   KOBOLD_LIVE_BIN=/path/to/koboldcpp KOBOLD_LIVE_MODEL=/path/to/small.gguf \
//     flutter test --tags kobold_live
//
// Every engine runs from a temp folder on its own port, so a KoboldCpp the
// machine already has running is never touched.

@Tags(['kobold_live'])
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold_process_control.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'live_engine.dart';

const _slow = Timeout(Duration(minutes: 8));

/// A swap host that lets the engine finish an unload before anything else
/// is asked of it. KoboldCpp acts on a request a moment after answering it,
/// and a reload that arrives in that moment is dropped; the app's own wait
/// for that is the swap rewrite's job, so this test waits for the engine
/// itself and checks only what it is here to check.
class _Settled implements GpuSwapHost {
  _Settled(this.host, this.port);
  final GpuSwapHost host;
  final int port;

  @override
  String get label => host.label;

  @override
  Future<void> unload() async {
    await host.unload();
    await waitForLiveUnload(port);
  }

  @override
  Future<void> restore() => host.restore();
}

void main() {
  late Directory root;

  // `flutter test` answers every HTTP call itself unless this is cleared.
  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    final temp = await Directory.systemTemp.createTemp('fpai kobold live');
    root = Directory(temp.resolveSymbolicLinksSync());
  });

  tearDown(() async {
    // Only what was started from this test's own folder.
    await Process.run('pkill', koboldOwnedKillArgs('${root.path}/'));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await root.delete(recursive: true);
  });

  test(
    'cleaning up orphans stops every process of an engine in the app\'s '
    'folder and leaves an engine run from another folder answering, even '
    'when that one loads a model kept in the app\'s folder',
    () async {
      final appFolder = Directory(p.join(root.path, 'app', 'koboldcpp_bin'));
      final otherFolder = Directory(p.join(root.path, 'my own tools'));
      final mine = await copyEngineInto(appFolder);
      final theirs = await copyEngineInto(otherFolder);
      final minePort = await freePort();
      final theirPort = await freePort();

      // The other engine's command line names the app's folder: its model
      // is reached through a link kept there.
      final borrowed = Link(p.join(appFolder.path, 'borrowed.gguf'))
        ..createSync(liveEngineModel);

      Future<void> start(String exe, int port, String model) async {
        final engine = await Process.start(exe, [
          '--model',
          model,
          '--port',
          '$port',
          '--contextsize',
          '2048',
          '--skiplauncher',
        ]);
        // Read and drop its log, or the engine blocks on a full pipe.
        engine.stdout.drain<void>().ignore();
        engine.stderr.drain<void>().ignore();
      }

      await start(mine, minePort, liveEngineModel);
      await start(theirs, theirPort, borrowed.path);
      await waitForLiveModel(minePort);
      await waitForLiveModel(theirPort);

      // The real engine is more than one process; all of them carry the
      // path they were started from.
      expect(
        (await livePidsStartedFrom('${appFolder.path}/')).length,
        greaterThan(1),
      );

      final log = <String>[];
      await killOrphanedKoboldProcesses(log.add, binDir: appFolder.path);
      await Future<void>.delayed(const Duration(seconds: 2));

      expect(await livePidsStartedFrom('${appFolder.path}/'), isEmpty);
      expect(await liveLoadedModel(minePort), isNull);
      expect(
        await liveLoadedModel(theirPort),
        isNotNull,
        reason: 'an engine the app did not start must keep running',
      );
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );

  test(
    'when something else reloads the real engine, the next held call puts '
    'the lane\'s own config back; the load counter moves on every change',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
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
      final kobold = KoboldService(storage);
      addTearDown(() async {
        await kobold.stopKobold();
        kobold.dispose();
      });
      final exe = await copyEngineInto(storage.binDir);
      final port = await freePort();
      kobold.setBaseUrl('http://127.0.0.1:$port');

      // Two presets for the one model, told apart by context size.
      String preset(String name, int context) {
        final file = File(p.join(root.path, name))
          ..writeAsStringSync('{"contextsize": $context, "gpulayers": 0}');
        return file.path;
      }

      final chatPreset = preset('chat.kcpps', 4096);
      final lanePreset = preset('lane.kcpps', 2048);

      GpuSwapHost host(String kcpps) => _Settled(
        KoboldProcessHost(
          baseUrl: kobold.baseUrl,
          requestedModelPath: liveEngineModel,
          requestedKcppsPath: kcpps,
          launchedKcppsPath: () => kobold.loadedKcppsPath ?? '',
          swapLock: kobold.adminSwapLock,
          adminDir: koboldAdminDirFor(storage),
          noteLoadedPair: (model, kcpps) =>
              kobold.noteAdminLoadedPair(modelPath: model, kcppsPath: kcpps),
          stopProcess: kobold.stopKobold,
          startProcess: () async =>
              fail('a swap must reload the running engine, not restart it'),
          isProcessRunning: () => kobold.isProcessRunning,
          markNotReady: kobold.markModelNotReady,
          waitUntilReady: () => kobold.waitUntilReadyAfterSwap(attempts: 240),
          admin: HttpGpuSwapHost(
            kind: LocalSwapKind.koboldProcess,
            apiUrl: kobold.baseUrl,
            modelId: liveEngineModel,
          ),
        ),
        port,
      );

      final before = kobold.loadGeneration;
      await kobold.startKobold(exe, liveEngineModel, port: port);
      await waitForLiveModel(port);
      final started = kobold.loadGeneration;
      expect(started, greaterThan(before), reason: 'a start is a load change');

      final chat = host(chatPreset);
      final lane = host(lanePreset);
      final occupancy = GpuSwapOccupancy(
        mouth: chat,
        worker: lane,
        residentGeneration: () => kobold.loadGeneration,
      );
      Future<int?> context() => liveContextSize(port);

      expect(await occupancy.hold(context), 2048);
      final laneLoaded = kobold.loadGeneration;
      expect(laneLoaded, greaterThan(started));
      // A second call with nothing changed does not reload.
      expect(await occupancy.hold(context), 2048);
      expect(kobold.loadGeneration, laneLoaded);

      // Outside the lane: another swap puts the chat pair back, the way a
      // chat reply does (unload what is there, load the chat pair). Settings
      // loading a model and the engine restarting look the same to the lane.
      await lane.unload();
      await chat.restore();
      expect(await context(), 4096);
      expect(kobold.loadGeneration, greaterThan(laneLoaded));

      expect(
        await occupancy.hold(context),
        2048,
        reason: 'the lane must not run on the chat config it was left with',
      );

      await occupancy.ensureMouth();
      expect(await context(), 4096);

      final beforeStop = kobold.loadGeneration;
      await kobold.stopKobold();
      expect(kobold.loadGeneration, greaterThan(beforeStop));
      expect(await liveLoadedModel(port), isNull);
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );
}
