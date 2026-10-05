// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The app's KoboldCpp answers this computer only. KoboldCpp's own default is
// every network the computer is on, which let any device on the same Wi-Fi
// call its admin endpoints and read the last reply. The command line is
// frozen, so the address rides in the config the app stages: KoboldCpp
// applies `host` from `--config` at launch and never changes it on a live
// reload (`test/live/kobold_host_live_test.dart` pins that on a real engine).
//
// Here: every config the app stages for a launch or a swap says 127.0.0.1,
// whatever the preset it starts from said, and the user's preset file is
// never edited.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:path/path.dart' as p;

import 'loopback_kobold.dart';

void main() {
  late Directory root;
  late KoboldRig rig;
  late String model;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('fpai listen address');
    rig = await KoboldRig.start(root);
    model = rig.gguf('chat-model.gguf');
    await rig.storage.backendSettings.setLastUsedModelPath(model);
  });

  tearDown(() async {
    await rig.close();
    root.deleteSync(recursive: true);
  });

  /// The launch the app makes for chat, and the config it staged for it.
  Future<({List<String> args, Map<String, dynamic> config})> launch({
    String? preset,
  }) async {
    final args = await buildKoboldLaunchArgs(
      storage: rig.storage,
      executablePath: '',
      modelPath: preset == null ? model : '',
      kcppsPath: preset,
      mmprojPath: null,
      port: 5001,
      gpuLayers: 0,
      contextSize: 8192,
      useVulkan: false,
      useCublas: false,
      useMetal: false,
      useRocm: false,
    );
    final staged = File(args[args.indexOf('--config') + 1]);
    return (
      args: args,
      config: (jsonDecode(staged.readAsStringSync()) as Map)
          .cast<String, dynamic>(),
    );
  }

  test('the config the launch writes from the app\'s own settings names '
      '127.0.0.1, and the command line stays as it was', () async {
    final (:args, :config) = await launch();

    expect(config['host'], '127.0.0.1');
    expect(args, isNot(contains('--host')));
    expect(args, isNot(contains('--adminpassword')));
  });

  test('a preset\'s own host is replaced by it, and the preset file is '
      'left as the user wrote it', () async {
    // KoboldCpp's own export says "" (every network); the others name a
    // network address or ask for the same by another spelling.
    final hosts = <Object?>['', '0.0.0.0', '192.168.1.20', '::', null];
    for (final (i, host) in hosts.indexed) {
      final file = rig.preset('Shared-$i.kcpps', {
        'model_param': model,
        'contextsize': 4096,
        'host': host,
      });
      final written = file.readAsStringSync();

      final (:config, args: _) = await launch(preset: file.path);

      expect(config['host'], '127.0.0.1', reason: 'the preset said "$host"');
      expect(file.readAsStringSync(), written);
    }
  });

  test('a preset that says nothing about its host gets it too', () async {
    final file = rig.preset('Silent.kcpps', {'model_param': model});

    final (:config, args: _) = await launch(preset: file.path);

    expect(config['host'], '127.0.0.1');
  });

  test('every config a swap stages names it: chat\'s, and the ones for '
      'another model with or without a preset of its own', () async {
    final laneModel = rig.gguf('lane-model.gguf');
    final lanPreset = rig.preset('Lan.kcpps', {
      'model_param': laneModel,
      'host': '0.0.0.0',
    });
    for (final kcpps in ['', lanPreset.path]) {
      final job = rig.provider.laneHost(
        type: 'kobold',
        url: '',
        model: laneModel,
        kcpps: kcpps,
      )!;
      await job.hold(() async {});
      await job.restore();
    }

    final staged = Directory(koboldAdminDirFor(rig.storage))
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith(kStagedConfigPrefix))
        .toList();
    expect(
      staged.map((f) => p.basename(f.path)),
      contains(kStagedChatConfig),
      reason: 'chat\'s own config was staged by the swap back',
    );
    expect(
      staged.where((f) => p.basename(f.path).startsWith('fpai-lane-')),
      hasLength(2),
      reason: 'one config for each of the two jobs',
    );
    for (final file in staged) {
      expect(
        (jsonDecode(file.readAsStringSync()) as Map)['host'],
        '127.0.0.1',
        reason: p.basename(file.path),
      );
    }
  });
}
