// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Presets written by the app's own writer, loaded by a REAL KoboldCpp.
// Skipped unless KOBOLD_LIVE_BIN and KOBOLD_LIVE_MODEL are set; see
// kobold_engine_live_test.dart.

@Tags(['kobold_live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:path/path.dart' as p;

import 'live_engine.dart';

const _slow = Timeout(Duration(minutes: 8));

void main() {
  late Directory root;
  late Directory adminDir;
  late String exe;
  late int port;

  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    final temp = await Directory.systemTemp.createTemp('fpai kcpps live');
    root = Directory(temp.resolveSymbolicLinksSync());
    adminDir = Directory(p.join(root.path, 'admin'))..createSync();
    exe = await copyEngineInto(Directory(p.join(root.path, 'koboldcpp_bin')));
    port = await freePort();
  });

  tearDown(() async {
    await stopLiveEnginesUnder(root);
    await root.delete(recursive: true);
  });

  /// Writes [config] with the app's writer into the admin folder and starts
  /// the engine from it, the way the app launches.
  Future<LiveEngine> launch(String name, KoboldLaunchConfig config) async {
    final staged = File(p.join(adminDir.path, name))
      ..writeAsStringSync(writeKcpps(config));
    final engine = await LiveEngine.start(exe, [
      '--config',
      staged.path,
      '--port',
      '$port',
      '--admin',
      '--admindir',
      adminDir.path,
    ]);
    await waitForLiveModel(port);
    return engine;
  }

  test(
    'a preset the app wrote is in force on the real engine, at a batch size '
    'the launcher does not list, and still in force after a live reload',
    () async {
      final engine = await launch(
        'fpai-live.kcpps',
        KoboldLaunchConfig(
          modelPath: liveEngineModel,
          contextSize: 4096,
          batchSize: 1536,
          kvQuant: KvQuant.q8_0,
        ),
      );

      expect(await liveContextSize(port), 4096);
      expect(engine.printed('n_ubatch').last, '1536');
      expect(engine.log, contains('q8_0'));

      // The same file again, live. A setting written only under its old
      // name would fall back to the default here (512).
      final reloads = engine.printed('n_ubatch').length;
      expect(
        await livePost(port, '/api/admin/reload_config', {
          'filename': 'fpai-live.kcpps',
        }),
        {'success': true},
      );
      await engine.waitForPrinted('n_ubatch', reloads + 1);
      await waitForLiveModel(port);

      expect(engine.printed('n_ubatch').last, '1536');
      expect(await liveContextSize(port), 4096);
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );

  test(
    'draft settings in a preset the app did not write survive its read and '
    'write, and the real engine drafts with them',
    () async {
      // As KoboldCpp's own launcher would save it. The draft model is the
      // model itself, so the vocabularies match.
      final theirs = jsonEncode({
        'model_param': liveEngineModel,
        'contextsize': 4096,
        'noswa': true,
        'draftmodel': liveEngineModel,
        'draftamount': 6,
      });
      final read = readKcpps(theirs) as KcppsOk;
      expect(read.unmanagedKeys, containsAll(['draftmodel', 'draftamount']));

      await launch('fpai-draft.kcpps', read.config);
      final reply = await livePost(port, '/api/v1/generate', {
        'prompt': 'Give me the first 40 integers: 1, 2, 3,',
        'max_length': 60,
        'temperature': 0,
      });
      expect(reply, isA<Map<dynamic, dynamic>>());

      final perf = await liveGet(port, '/api/extra/perf');
      expect(
        (perf as Map)['last_draft_success'],
        greaterThan(0),
        reason: 'drafted tokens were accepted, so the draft model is in use',
      );
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );
}
