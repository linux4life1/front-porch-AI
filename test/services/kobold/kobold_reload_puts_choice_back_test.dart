// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A reload of chat that KoboldCpp could not load, where the old model is kept
// running (see kobold_reload_keeps_engine_test): the choice the pick stored
// goes back to what KoboldCpp is actually running, so every screen names the
// running model. The words still say why the new one was not loaded.
//
// What the engine runs is what the service recorded as loaded before the
// reload, checked against what the engine itself reports: a record the engine
// does not agree with is not put back, and neither is a choice that changed
// while the reload was in flight.
//
// The engine is a real HTTP server on loopback (see loopback_kobold.dart);
// the app's own reload, storage and swap code run against it.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/services.dart';

import 'loopback_kobold.dart';

void main() {
  late Directory root;
  late KoboldRig rig;
  late String oldModel;
  late String oldPreset;

  backend() => rig.storage.backendSettings;
  Map<String, String> links() => rig.storage.presetSettings.modelPresetMap;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('fpai put back');
    rig = await KoboldRig.start(root);
    oldModel = rig.gguf('old.gguf');
    oldPreset = rig.preset('Old.kcpps', {'contextsize': 8192}).path;
    // Chat runs the old model on the old preset: as the user chose it, and as
    // a launch recorded it.
    await backend().setLastUsedModelPath(oldModel);
    await backend().setActiveKcppsPath(oldPreset);
    await rig.storage.presetSettings.setModelPreset(oldModel, oldPreset);
    rig.kobold.noteAdminLoadedPair(modelPath: oldModel, kcppsPath: oldPreset);
    File(p.join(rig.engine.adminDir, kStagedChatConfig)).writeAsStringSync(
      jsonEncode({'model_param': oldModel, 'contextsize': 8192}),
    );
    // KoboldCpp goes back to this when a config does not load.
    rig.engine.model = rig.engine.startupModel = 'koboldcpp/old';
  });

  tearDown(() async {
    await rig.close();
    root.deleteSync(recursive: true);
  });

  /// A file a fresh start would refuse: not a GGUF.
  String broken(String name) => (File(
    p.join(root.path, name),
  )..writeAsBytesSync('XXXX'.codeUnits + List.filled(32, 0))).path;

  /// The model the staged chat config loads: what an idle unload loads back.
  String stagedModel() =>
      (jsonDecode(
                File(
                  p.join(rig.engine.adminDir, kStagedChatConfig),
                ).readAsStringSync(),
              )
              as Map)['model_param']
          as String;

  void expectChoiceIsTheOldOne() {
    expect(backend().lastUsedModelPath, oldModel);
    expect(backend().activeKcppsPath, oldPreset);
    expect(links()[oldModel], oldPreset);
  }

  group('the old model is kept running', () {
    test('a model the phone or Settings picked, which KoboldCpp could not '
        'load: the choice goes back to the model that runs', () async {
      final newModel = broken('new.gguf');
      rig.engine.failing.add(kStagedChatConfig);
      await selectKoboldModel(rig.storage, newModel);
      expect(
        backend().lastUsedModelPath,
        newModel,
        reason: 'the pick is stored',
      );

      final result = await rig.provider.reloadChatKobold();

      expect(result?.refusal, contains('The previous one is still running'));
      expect(result?.refusal, contains('Not a valid GGUF'));
      expect(rig.engine.model, 'koboldcpp/old');
      expect(rig.kobold.running, isTrue);
      expectChoiceIsTheOldOne();
    });

    test('the service records what runs, and the staged chat config is '
        'the running model\'s, so an idle unload loads that back', () async {
      final newModel = broken('new.gguf');
      rig.engine.failing.add(kStagedChatConfig);
      await selectKoboldModel(rig.storage, newModel);

      await rig.provider.reloadChatKobold();

      expect(rig.kobold.loadedModelPath, oldModel);
      expect(rig.kobold.loadedKcppsPath, oldPreset);
      expect(stagedModel(), oldModel);
    });

    test('a preset that asks KoboldCpp to run a program, picked: refused '
        'before anything is sent, and the choice goes back', () async {
      final risky = rig.preset('Risky.kcpps', {
        'contextsize': 8192,
        'mcpfile': 'https://example.com/servers.json',
      });
      await chooseKoboldPreset(rig.storage, risky.path);
      expect(backend().activeKcppsPath, risky.path);
      expect(links()[oldModel], risky.path, reason: 'the pick wrote its link');

      final result = await rig.provider.reloadChatKobold();

      expect(result?.refusal, contains('mcpfile'));
      expect(rig.engine.reloads, isEmpty);
      expectChoiceIsTheOldOne();
    });

    test('a preset that names a model KoboldCpp could not load: the model '
        'and the preset in use are the running ones again', () async {
      final newModel = broken('new.gguf');
      final owns = rig.preset('Owns.kcpps', {
        'model_param': newModel,
        'contextsize': 8192,
      });
      rig.engine.failing.add(kStagedChatConfig);
      await chooseKoboldPreset(rig.storage, owns.path);
      expect(
        backend().lastUsedModelPath,
        newModel,
        reason: 'the preset owns it',
      );

      final result = await rig.provider.reloadChatKobold();

      expect(result?.refusal, contains('The previous one is still running'));
      expectChoiceIsTheOldOne();
      expect(
        links()[newModel],
        owns.path,
        reason: 'what the user linked to the new model is theirs, and stays',
      );
    });

    test('a second model that does not load goes back too: the record was '
        'put back with the choice', () async {
      rig.engine.failing.add(kStagedChatConfig);
      for (final name in ['first.gguf', 'second.gguf']) {
        await selectKoboldModel(rig.storage, broken(name));
        final result = await rig.provider.reloadChatKobold();

        expect(result?.refusal, isNotNull, reason: name);
        expectChoiceIsTheOldOne();
      }
    });
  });

  group('what is not put back', () {
    test('a model a fresh start can run is not a kept reload: the engine is '
        'restarted on the new choice, which stays', () async {
      final newModel = rig.gguf('new.gguf');
      rig.engine.failing.add(kStagedChatConfig);
      await selectKoboldModel(rig.storage, newModel);

      await rig.provider.reloadChatKobold();

      expect(rig.kobold.launches, 1);
      expect(backend().lastUsedModelPath, newModel);
    });

    test('with no record of what is loaded, nothing is guessed', () async {
      final newModel = broken('new.gguf');
      rig.engine.failing.add(kStagedChatConfig);
      rig.kobold.forgetAdminLoadedPair();
      await selectKoboldModel(rig.storage, newModel);

      final result = await rig.provider.reloadChatKobold();

      expect(result?.refusal, isNotNull, reason: 'it still says why');
      expect(backend().lastUsedModelPath, newModel);
    });

    test('a record the engine does not agree with is not put back', () async {
      // The engine went back to a model other than the one recorded: say, a
      // helper model was loaded when the reload came.
      rig.engine.model = rig.engine.startupModel = 'koboldcpp/helper';
      final newModel = broken('new.gguf');
      rig.engine.failing.add(kStagedChatConfig);
      await selectKoboldModel(rig.storage, newModel);

      final result = await rig.provider.reloadChatKobold();

      expect(result?.refusal, isNotNull);
      expect(backend().lastUsedModelPath, newModel);
    });

    test('a choice made while the reload was running is the user\'s newer '
        'one, and stays', () async {
      final first = broken('first.gguf');
      final second = broken('second.gguf');
      rig.engine.failing.add(kStagedChatConfig);
      await selectKoboldModel(rig.storage, first);

      final reload = rig.provider.reloadChatKobold();
      await selectKoboldModel(rig.storage, second);
      final result = await reload;

      expect(result?.refusal, isNotNull);
      expect(rig.kobold.launches, 0, reason: 'a kept reload, not a restart');
      expect(backend().lastUsedModelPath, second);
    });
  });
}
