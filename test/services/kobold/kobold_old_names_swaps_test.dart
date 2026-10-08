// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A preset an older KoboldCpp saved, with old setting names and not the
// current ones, must not reach a RUNNING engine either: KoboldCpp drops the
// old names on a live reload, so the preset would run differently from the
// way it started. Not when chat's preset is changed (a live reload by name),
// not when a helper or story model swaps in with such a preset, and not when
// the preset editor times one. The engine here is a real HTTP server on
// loopback that records what it is asked to reload; the app's own swap code
// runs against it end to end. (The same checks as for a preset that would
// run a program: kobold_risky_preset_swaps_test.)

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/services.dart';

import 'loopback_kobold.dart';

/// What the refusal says, for a preset with these old names.
Matcher _refusal(List<String> names) => allOf([
  for (final n in names) contains(n),
  contains('saved by an older KoboldCpp'),
  contains('press Save'),
  contains('pick another preset'),
]);

void main() {
  late Directory root;
  late KoboldRig rig;
  late String chatModel;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('fpai old names swaps');
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

  test('chat\'s preset changed to an old-style one is not loaded into the '
      'running engine, and nothing is stopped', () async {
    final old = rig.preset('Old.kcpps', {
      'contextsize': 8192,
      'blasbatchsize': 1024,
      'flashattention': false,
    });
    await rig.storage.backendSettings.setActiveKcppsPath(old.path);

    final result = await rig.provider.reloadChatKobold();

    expect(
      result?.refusal,
      allOf(
        contains('The previous one is still running'),
        _refusal(['blasbatchsize', 'flashattention']),
      ),
    );
    expect(rig.engine.reloads, isEmpty, reason: 'KoboldCpp was never asked');
    expect(staged(), isNot(contains(kStagedChatConfig)));
    expect(rig.kobold.running, isTrue, reason: 'the working engine is left');
    expect(rig.kobold.launches, 0);
    expect(
      rig.kobold.modelLoadingStatus,
      _refusal(['blasbatchsize', 'flashattention']),
      reason: 'the status line, which the phone\'s Local model card shows',
    );
  });

  test(
    'a helper or story model swapped in with an old-style preset is '
    'refused at the swap, and the preset is never staged or loaded',
    () async {
      final helperModel = rig.gguf('helper.gguf');
      final old = rig.preset('Helper.kcpps', {
        'contextsize': 8192,
        'usecublas': ['normal', '0'],
      });
      final lane = rig.provider.laneHost(
        type: 'kobold',
        url: '',
        model: helperModel,
        kcpps: old.path,
      )!;

      await expectLater(
        lane.hold(() async => fail('the job must not run on a refused preset')),
        throwsA(
          isA<KoboldPresetProblem>().having(
            (e) => e.message,
            'message',
            _refusal(['usecublas']),
          ),
        ),
      );

      expect(
        rig.engine.reloads.where((name) => name.contains('lane')),
        isEmpty,
        reason: 'the engine was never asked for the helper\'s config',
      );
      expect(staged().where((name) => name.contains('lane')), isEmpty);
    },
  );

  test('a timing trial of a config with an old setting name alone is '
      'refused where it is loaded, whoever built the config', () async {
    final config = {
      'model_param': chatModel,
      'contextsize': 8192,
      'useswa': false,
    };

    await expectLater(
      rig.provider.loadKoboldTrial('fpai-trial.kcpps', config),
      throwsA(
        isA<KoboldPresetProblem>().having(
          (e) => e.message,
          'message',
          _refusal(['useswa']),
        ),
      ),
    );

    expect(rig.engine.reloads, isEmpty, reason: 'KoboldCpp was never asked');
    expect(staged(), isNot(contains('fpai-trial.kcpps')));
  });

  test('a timing trial with both spellings, as the app writes them, still '
      'loads', () async {
    final config = {
      'model_param': chatModel,
      'contextsize': 8192,
      'usecuda': ['normal', '0'],
      'usecublas': ['normal', '0'],
      'batchsize': 1024,
      'blasbatchsize': 1024,
    };

    expect(
      await rig.provider.loadKoboldTrial('fpai-trial.kcpps', config),
      isTrue,
    );
    expect(rig.engine.reloads, ['fpai-trial.kcpps']);
  });
}
