// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A preset that would make KoboldCpp run a program or open itself to the
// internet must not reach a RUNNING engine either: not when chat's preset is
// changed (a live reload by name), not when a helper or story model swaps in
// with such a preset, and not when the preset editor times one. The engine
// here is a real HTTP server on
// loopback that records what it is asked to reload; the app's own swap code
// runs against it end to end.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/services.dart';

import 'loopback_kobold.dart';

void main() {
  late Directory root;
  late KoboldRig rig;
  late String chatModel;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('fpai risky swaps');
    rig = await KoboldRig.start(root);
    chatModel = rig.gguf('chat.gguf');
    await rig.storage.backendSettings.setLastUsedModelPath(chatModel);
  });

  tearDown(() async {
    await rig.close();
    root.deleteSync(recursive: true);
  });

  /// Files staged for the engine, by name.
  List<String> staged() => [
    for (final f in Directory(rig.engine.adminDir).listSync())
      if (f is File) p.basename(f.path),
  ];

  test('chat\'s preset changed to a risky one is not loaded into the running '
      'engine, and nothing is stopped', () async {
    final risky = rig.preset('Risky.kcpps', {
      'contextsize': 8192,
      'mcpfile': 'https://example.com/servers.json',
    });
    await rig.storage.backendSettings.setActiveKcppsPath(risky.path);

    // Whether the refusal comes back as a result or is thrown is the
    // caller's contract (kobold_reload_keeps_engine_test); here it is only
    // that it is a refusal.
    try {
      await rig.provider.reloadChatKobold();
    } on KoboldPresetProblem catch (e) {
      expect(e.message, contains('mcpfile'));
    }

    expect(rig.engine.reloads, isEmpty, reason: 'KoboldCpp was never asked');
    expect(staged(), isNot(contains(kStagedChatConfig)));
    expect(rig.kobold.running, isTrue, reason: 'the working engine is left');
    expect(rig.kobold.launches, 0);
  });

  test('a helper or story model swapped in with a risky preset is refused '
      'at the swap, and the preset is never staged or loaded', () async {
    final helperModel = rig.gguf('helper.gguf');
    final risky = rig.preset('Helper.kcpps', {
      'contextsize': 8192,
      'remotetunnel': true,
    });
    final lane = rig.provider.laneHost(
      type: 'kobold',
      url: '',
      model: helperModel,
      kcpps: risky.path,
    )!;

    await expectLater(
      lane.hold(() async => fail('the job must not run on a refused preset')),
      throwsA(
        isA<KoboldPresetProblem>().having(
          (e) => e.message,
          'message',
          allOf(contains('remotetunnel'), contains('pick another preset')),
        ),
      ),
    );

    expect(
      rig.engine.reloads.where((name) => name.contains('lane')),
      isEmpty,
      reason: 'the engine was never asked for the helper\'s config',
    );
    expect(staged().where((name) => name.contains('lane')), isEmpty);
  });

  test('a timing trial of a config that would run a program is refused '
      'where it is loaded, whoever built the config', () async {
    // The editor builds its trial through the launch map, which refuses such
    // a config; loadKoboldTrial is public and stages what it is given.
    final config = {
      'model_param': chatModel,
      'contextsize': 8192,
      'mcpfile': 'https://example.com/servers.json',
    };

    await expectLater(
      rig.provider.loadKoboldTrial('fpai-trial.kcpps', config),
      throwsA(
        isA<KoboldPresetProblem>().having(
          (e) => e.message,
          'message',
          allOf(contains('mcpfile'), contains('pick another preset')),
        ),
      ),
    );

    expect(rig.engine.reloads, isEmpty, reason: 'KoboldCpp was never asked');
    expect(staged(), isNot(contains('fpai-trial.kcpps')));
  });

  test('a timing trial of a fine config still loads', () async {
    final config = {'model_param': chatModel, 'contextsize': 8192};

    expect(
      await rig.provider.loadKoboldTrial('fpai-trial.kcpps', config),
      isTrue,
    );
    expect(rig.engine.reloads, ['fpai-trial.kcpps']);
  });
}
