// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The Local model card's speed test (the maintainer's ruling, 2026-10-06),
// run for real: the app's KoboldCpp service, its provider, staging, trial
// reloads and chat reload, on a loopback KoboldCpp that reloads staged
// configs by name and prints the speed of each timing prompt for the config
// it really loaded. One setting at a time: the physical batch, then MMQ,
// mmap and flash attention (memory lock is not offered with automatic
// layers). The winner is saved as a real preset, linked to the model, and
// what auto mode launches from then on.
//
// The engine's speeds: reading is faster at a larger physical batch and with
// MMQ off; writing is faster with mmap off and slower with flash attention
// off. A turn is reading 1,000 tokens and writing 200, so the expected winner
// is a physical batch of 2,048, MMQ off, mmap off, flash attention on.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../helpers/chat_db_teardown.dart';
import 'speed_test_rig.dart';

({double read, double write}) _speeds(Map<String, dynamic> c) {
  final batch = kcppsBatchOf(c).physical;
  final read =
      1000.0 *
      (switch (batch) {
        512 => 1.0,
        1024 => 1.25,
        _ => 1.6,
      }) *
      (c['nommq'] == true ? 1.1 : 1.0);
  final write =
      200.0 *
      (c['usemmap'] == false ? 1.08 : 1.0) *
      (c['noflashattention'] == true ? 0.8 : 1.0);
  return (read: read, write: write);
}

Map<String, dynamic> _file(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as Map).cast<String, dynamic>();

void main() {
  late Directory root;
  late SpeedTestRig rig;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fpai speed test run');
    rig = await SpeedTestRig.start(root, _speeds);
  });

  tearDown(() async {
    await rig.close();
    await root.delete(recursive: true);
  });

  String presetPath() => p.join(
    rig.storage.binDir.path,
    'Qwen3 14B (measured on GeForce RTX 4090).kcpps',
  );

  test('one setting at a time, the winner saved as a real preset, linked to '
      'the model, put in place, and launched with from then on', () async {
    final asked = await rig.test.ask();
    expect(asked.refusal, isNull);
    expect(asked.ask, startsWith('This takes '));
    expect(await rig.test.start(), isNull);
    await rig.finished();

    // Six timings: what ran (no reload), 512 and 2,048, then MMQ off, mmap
    // off and flash attention off each with the best so far; and one last
    // reload of chat's own config, since the last try is not the winner.
    expect(rig.engine.timings, 6);
    expect(rig.engine.reloads, [
      ...List.filled(5, kSpeedTrialConfig),
      kStagedChatConfig,
    ]);
    expect(rig.test.phase, KoboldSpeedPhase.done);
    expect(
      rig.test.line,
      matches(RegExp(r'^Replies now come about 1[5-9]% sooner\.$')),
    );

    // The winner as a real preset, read back through the codec.
    final read = readKcpps(File(presetPath()).readAsStringSync()) as KcppsOk;
    final c = read.config;
    expect(c.batchSize, 2048);
    expect(c.logicalBatchSize, kKoboldLogicalBatch, reason: 'KoboldCpp 1.122');
    expect(c.mmq, isFalse);
    expect(c.useMmap, isFalse);
    expect(c.useMlock, isFalse);
    expect(c.flashAttention, isTrue);
    expect(c.modelPath, rig.model);
    expect(c.measured?.card, SpeedTestRig.card);
    expect(c.measured?.backend, 'cuda');
    expect(c.measured?.engine, '1.122.1');
    expect(c.measured?.auto, isTrue);
    expect(read.unmanagedKeys, isEmpty, reason: 'a preset like any other');
    expect(read.raw.containsKey('host'), isFalse);

    // The model's own preset, and auto mode kept: the card stays the card.
    expect(rig.storage.presetSettings.modelPresetMap[rig.model], presetPath());
    expect(rig.storage.backendSettings.activeKcppsPath, isNull);

    // What the engine runs now is the winner.
    final now = rig.engine.loaded;
    expect(kcppsBatchOf(now).physical, 2048);
    expect(now['nommq'], isTrue);
    expect(now['usemmap'], isFalse);
    expect(now['noflashattention'], isFalse);

    // The next start of that model, through the one launch resolver.
    final launch = resolveKoboldLaunch(rig.storage);
    expect(launch.kcppsPath, isNull);
    final args = await buildKoboldLaunchArgs(
      storage: rig.storage,
      executablePath: p.join(rig.storage.binDir.path, 'koboldcpp'),
      modelPath: launch.modelPath,
      kcppsPath: launch.kcppsPath,
      mmprojPath: null,
      port: 5001,
      gpuLayers: 0,
      contextSize: rig.storage.backendSettings.contextSize,
      useVulkan: false,
      useCublas: false,
      useMetal: false,
      useRocm: false,
      hardware: rig.kobold.hardwareInfo!(),
      free: rig.kobold.freeBeforeLaunch,
    );
    final next = _file(args[args.indexOf('--config') + 1]);
    expect(kcppsBatchOf(next).physical, 2048);
    expect(next['nommq'], isTrue);
    expect(next['usemmap'], isFalse);
  });

  test('while the preset editor times a setting, the card says a test is '
      'running, also while a try loads', () async {
    final letGo = await rig.kobold.holdForSpeedTest();
    rig.kobold.markModelLoading('Loading a try…');
    expect(await rig.test.why(), 'A speed test is already running.');
    expect(await rig.test.start(), 'A speed test is already running.');
    letGo();
  });

  test('picking the model again in auto mode keeps auto mode', () async {
    expect(await rig.test.start(), isNull);
    await rig.finished();
    await selectKoboldModel(rig.storage, rig.model);
    expect(rig.storage.backendSettings.activeKcppsPath, isNull);
  });

  test('Cancel stops after the step under way and puts the model back as it '
      'was; nothing is saved', () async {
    rig.engine.beforeTiming = (n) async {
      if (n == 2) rig.test.cancel();
    };
    expect(await rig.test.start(), isNull);
    await rig.finished();
    expect(rig.test.phase, KoboldSpeedPhase.stopped);
    expect(rig.test.line, 'Stopped. Your settings were not changed.');
    expect(rig.engine.timings, 2);
    expect(rig.engine.reloads, [kSpeedTrialConfig, kStagedChatConfig]);
    expect(kcppsBatchOf(rig.engine.loaded).physical, 1024);
    expect(File(presetPath()).existsSync(), isFalse);
    expect(rig.storage.presetSettings.modelPresetMap[rig.model], isNull);
  });

  test('a message sent while it runs is refused with how long is left, and '
      'reaches neither the chat nor the engine', () async {
    final db = AppDatabase.forTesting();
    final chat =
        ChatService(
            rig.kobold,
            UserPersonaService(db),
            rig.storage,
            WorldRepository(rig.storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, rig.storage))
          ..setLLMProvider(rig.llm);
    addTearDown(() => disposeChatThenCloseDb(chat, db));
    final character = CharacterCard(
      name: 'Ada',
      description: 'Keeps the porch.',
      firstMessage: 'Evening.',
      imagePath: '/tmp/Ada-speed-test.png',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: false,
        needsSimEnabled: false,
      ),
    );
    await CharacterRepository(db, rig.storage).addCharacter(character);
    await chat.setActiveCharacter(character);
    final before = chat.messages.length;

    final holding = Completer<void>();
    final release = Completer<void>();
    rig.engine.beforeTiming = (n) async {
      if (n != 1) return;
      holding.complete();
      await release.future;
    };
    expect(await rig.test.start(), isNull);
    await holding.future;
    await chat.sendMessage('Are you still there?');
    expect(chat.guestActivityStatus, startsWith('Testing speed settings, '));
    expect(chat.guestActivityStatus, endsWith(' left.'));
    expect(chat.messages.length, before);
    expect(chat.sendRefusal('/expression happy'), isNull, reason: 'no model');
    release.complete();
    await rig.finished();
    expect(chat.sendRefusal('Are you still there?'), isNull);
  });
}
