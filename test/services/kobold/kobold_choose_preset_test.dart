// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Choosing a preset keeps it for the model a launch will load: the one
// function Settings (from the list and with Browse) and the phone share. The
// files are real; a preset that names a model names a file on this disk.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/services.dart';

import '../../golden/support/fakes_storage.dart';

void main() {
  late Directory dir;
  late FakeStorageService storage;

  /// A file with the GGUF magic, enough for the app's model check.
  String model(String name) => (File(
    p.join(dir.path, name),
  )..writeAsBytesSync('GGUF'.codeUnits + List.filled(32, 0))).path;

  String preset(String name, String json) =>
      (File(p.join(dir.path, name))..writeAsStringSync(json)).path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fpai choose preset');
    storage = FakeStorageService();
  });

  // The storage double is left undisposed: its constructor starts setters
  // that finish (and notify) after a quick test has already ended.
  tearDown(() => dir.deleteSync(recursive: true));

  test('a preset that names a model on this disk is kept for that model, '
      'which becomes the model in use', () async {
    final a = model('a.gguf');
    final b = model('b.gguf');
    final owned = preset('b.kcpps', '{"model_param": "$b"}');
    await storage.backendSettings.setLastUsedModelPath(a);

    final kept = await chooseKoboldPreset(storage, owned);

    expect(kept, b);
    expect(storage.backendSettings.activeKcppsPath, owned);
    expect(storage.backendSettings.lastUsedModelPath, b);
    expect(storage.presetSettings.modelPresetMap[b], owned);
    expect(storage.presetSettings.modelPresetMap[a], isNull);
  });

  test('a preset that names no model is kept for the model in use', () async {
    final a = model('a.gguf');
    final plain = preset('plain.kcpps', '{"contextsize": 8192}');
    await storage.backendSettings.setLastUsedModelPath(a);

    expect(await chooseKoboldPreset(storage, plain), a);

    expect(storage.backendSettings.lastUsedModelPath, a);
    expect(storage.presetSettings.modelPresetMap[a], plain);
  });

  test(
    'choosing none clears the link of the model in use and no other',
    () async {
      final a = model('a.gguf');
      final b = model('b.gguf');
      final forA = preset('a.kcpps', '{"contextsize": 4096}');
      final forB = preset('b.kcpps', '{"contextsize": 8192}');
      await storage.presetSettings.setModelPreset(a, forA);
      await storage.presetSettings.setModelPreset(b, forB);
      await storage.backendSettings.setLastUsedModelPath(a);
      await storage.backendSettings.setActiveKcppsPath(forA);

      expect(await chooseKoboldPreset(storage, null), a);

      expect(storage.backendSettings.activeKcppsPath, isNull);
      expect(storage.presetSettings.modelPresetMap[a] ?? '', isEmpty);
      expect(storage.presetSettings.modelPresetMap[b], forB);
    },
  );

  test('with no model chosen yet the preset is chosen and nothing is '
      'kept', () async {
    final plain = preset('plain.kcpps', '{"contextsize": 8192}');

    expect(await chooseKoboldPreset(storage, plain), isNull);
    expect(storage.backendSettings.activeKcppsPath, plain);
    expect(storage.presetSettings.modelPresetMap, isEmpty);

    // An empty record is no model either.
    await storage.backendSettings.setLastUsedModelPath('');
    expect(await chooseKoboldPreset(storage, plain), isNull);
    expect(storage.presetSettings.modelPresetMap, isEmpty);
  });
}
