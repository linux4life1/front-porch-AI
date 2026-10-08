// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// KoboldCpp's own idle unload never runs. The app keeps its own timer
// (kobold_idle_unload_test.dart): it unloads the model and, before the next
// request, loads chat's setup back. KoboldCpp's timer cannot do that. Its
// wake-up exists only in router mode, and the app's requests name
// "koboldcpp", which the router does not wake. A preset that carries
// `adminunloadtimeout` above 0 (KoboldCpp's own launcher exports the key)
// would therefore unload the model behind the app's back, and the next reply
// would reach an engine with no model.
//
// The command line is frozen, so the 0 rides in the config the app stages,
// the way `host` does (kobold_listen_address_test.dart): KoboldCpp reads
// every key of `--config` at launch, and ignores this one on a live reload.
//
// Here: every config the app stages for a launch or a swap says 0, whatever
// the preset it starts from said, and the user's preset file is never edited.

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
    root = Directory.systemTemp.createTempSync('fpai admin unload');
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

  test('the config the launch writes from the app\'s own settings says 0, '
      'and the command line stays as it was', () async {
    final (:args, :config) = await launch();

    expect(config['adminunloadtimeout'], 0);
    expect(args, [
      '--config',
      p.join(koboldAdminDirFor(rig.storage), kStagedChatConfig),
      '--port',
      '5001',
      '--admin',
      '--admindir',
      koboldAdminDirFor(rig.storage),
    ]);
  });

  test('a preset that asks for KoboldCpp\'s idle unload is staged with 0, '
      'and the preset file is left as the user wrote it', () async {
    // The minutes KoboldCpp's launcher lets a user type, and the shapes a
    // hand-written file might give them.
    final asked = <Object?>[300, 1, 60, 86400, '300', null];
    for (final (i, minutes) in asked.indexed) {
      final file = rig.preset('Sleepy-$i.kcpps', {
        'model_param': model,
        'contextsize': 4096,
        'adminunloadtimeout': minutes,
      });
      final written = file.readAsStringSync();

      final (:config, args: _) = await launch(preset: file.path);

      expect(
        config['adminunloadtimeout'],
        0,
        reason: 'the preset said "$minutes"',
      );
      expect(file.readAsStringSync(), written);
    }
  });

  test('a preset that says nothing about it gets 0 too', () async {
    final file = rig.preset('Silent.kcpps', {'model_param': model});

    final (:config, args: _) = await launch(preset: file.path);

    expect(config['adminunloadtimeout'], 0);
  });

  test('every config a swap stages says 0: chat\'s, and the ones for '
      'another model with or without a preset of its own', () async {
    final laneModel = rig.gguf('lane-model.gguf');
    final sleepy = rig.preset('Sleepy.kcpps', {
      'model_param': laneModel,
      'adminunloadtimeout': 300,
    });
    for (final kcpps in ['', sleepy.path]) {
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
        (jsonDecode(file.readAsStringSync()) as Map)['adminunloadtimeout'],
        0,
        reason: p.basename(file.path),
      );
    }
  });

  test('a live reload of chat onto a preset that asks for the idle unload '
      'hands the engine a config that says 0', () async {
    final sleepy = rig.preset('Sleepy.kcpps', {
      'model_param': model,
      'adminunloadtimeout': 300,
    });
    await rig.storage.backendSettings.setActiveKcppsPath(sleepy.path);

    await rig.provider.reloadChatKobold();

    expect(rig.engine.reloads, [
      kStagedChatConfig,
    ], reason: 'the engine was asked to load chat\'s staged config by name');
    final sent = File(
      p.join(koboldAdminDirFor(rig.storage), kStagedChatConfig),
    ).readAsStringSync();
    expect((jsonDecode(sent) as Map)['adminunloadtimeout'], 0);
  });
}
