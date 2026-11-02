// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/services/gen_presets/gen_presets.dart';
import 'package:front_porch_ai/services/storage/storage.dart';

import '../golden/support/fakes_storage.dart';

/// Counts preset saves, for the one-write checks on save buttons.
class CountingGenPresets extends GenPresetSettings {
  int saves = 0;

  @override
  Future<void> savePreset(String name, SamplerValues values) {
    saves++;
    return super.savePreset(name, values);
  }
}

/// A storage double with the real preset store and model follower, wired as
/// [StorageService] wires them: the follower hears every settings change.
/// Its recommended values come from [rec] instead of a GGUF on disk.
class GenPresetStorage extends FakeStorageService {
  GenPresetStorage._(RecommendedSamplers Function(ChatModelId) rec) {
    _presets.initializeBase(null, notifyListeners);
    follower = GenPresetFollower(
      generation: generationSettings,
      backend: backendSettings,
      presets: _presets,
      lookup: (model) async => rec(model),
    );
  }

  final _presets = CountingGenPresets();
  late final GenPresetFollower follower;

  @override
  CountingGenPresets get genPresets => _presets;
  @override
  GenPresetFollower get genPresetFollower => follower;

  /// A local [modelPath] as the chat model, already seeded (not a switch).
  static Future<GenPresetStorage> create({
    String modelPath = '/models/Qwen3-8B-Q4_K_M.gguf',
    RecommendedSamplers Function(ChatModelId model)? rec,
  }) async {
    final s = GenPresetStorage._(rec ?? (_) => RecommendedSamplers.unknown);
    await s.backendSettings.setBackendType('kobold');
    await s.backendSettings.setLastUsedModelPath(modelPath);
    await s.follower.start();
    s.addListener(s.follower.onSettingsChanged);
    return s;
  }
}
