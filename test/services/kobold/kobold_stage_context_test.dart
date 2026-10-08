// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Chat's prompts are held to the context its KoboldCpp runs. A chat preset
// that names no context runs the engine's own default, which the app learns
// from the engine once a load is confirmed. Staging chat's config is not a
// load, and a swap back to chat stages it before every reply when two
// KoboldCpp roles share the engine: it must not forget what was learned,
// or prompts are no longer held to anything.
//
// The engine is a real HTTP server on loopback (see loopback_kobold.dart).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/services.dart';

import 'loopback_kobold.dart';

void main() {
  late Directory root;
  late KoboldRig rig;
  late String model;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('fpai stage context');
    rig = await KoboldRig.start(root);
    model = rig.gguf('chat-model.gguf');
    await rig.storage.backendSettings.setLastUsedModelPath(model);
  });

  tearDown(() async {
    await rig.close();
    root.deleteSync(recursive: true);
  });

  Future<KoboldStagedRole> stageChat(File preset) => stageKoboldRole(
    storage: rig.storage,
    executablePath: '',
    name: kStagedChatConfig,
    modelPath: model,
    kcppsPath: preset.path,
    mmprojPath: null,
    gpuLayers: 0,
    contextSize: 16384,
    useVulkan: false,
    useCublas: false,
    useMetal: false,
    useRocm: false,
  );

  test('a chat preset that names a context holds prompts to it at once, '
      'before the load is confirmed', () async {
    await stageChat(rig.preset('Named.kcpps', {'contextsize': 8192}));

    expect(rig.storage.backendSettings.engineContextSize, 8192);
  });

  test('a chat preset that names none leaves what the engine was seen to '
      'run', () async {
    rig.storage.backendSettings.setEngineContextSize(12288);

    await stageChat(rig.preset('Silent.kcpps', {'model_param': model}));

    expect(rig.storage.backendSettings.engineContextSize, 12288);
    expect(rig.storage.backendSettings.promptContext(32768), 12288);
  });

  test('chat already loaded and asked for again keeps the context the '
      'engine runs', () async {
    rig.engine.defaultContext = 12288;
    final preset = rig.preset('Silent.kcpps', {'model_param': model});
    await rig.storage.backendSettings.setActiveKcppsPath(preset.path);
    await rig.provider.reloadChatKobold();
    expect(rig.storage.backendSettings.engineContextSize, 12288);

    // As every reply does when chat shares the engine with a helper model:
    // staged again, found loaded already, nothing sent.
    await rig.provider.reloadChatKobold();

    expect(rig.engine.reloads, hasLength(1));
    expect(rig.storage.backendSettings.engineContextSize, 12288);
    expect(rig.storage.backendSettings.promptContext(32768), 12288);
  });
}
