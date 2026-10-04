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

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold_process_control.dart';
import 'package:path/path.dart' as p;

import 'live_engine.dart';

const _slow = Timeout(Duration(minutes: 8));

void main() {
  late Directory root;

  // `flutter test` answers every HTTP call itself unless this is cleared.
  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    final temp = await Directory.systemTemp.createTemp('fpai kobold live');
    root = Directory(temp.resolveSymbolicLinksSync());
  });

  tearDown(() async {
    await stopLiveEnginesUnder(root);
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
}
