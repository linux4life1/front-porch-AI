// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The app's own launch settings turned into a KoboldCpp config. The rule
// behind every case: KoboldCpp places the model in memory unless the user
// took that over, and the app never asks for a pairing or a lock that is
// known to hurt.
//
// Changed 2026-10-03: the case for `koboldPresetConfig` is gone with the
// function. It rebuilt a user's preset from the app's typed settings, which
// is how a launch came to drop a second graphics card and a MoE layer
// count. A preset is now launched from the file as written; what that case
// pinned (the resolved model, the chat template, the vision file, and
// everything else kept) is pinned on the real thing in
// kcpps_launch_map_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';

KoboldAppSettings _settings({
  bool layersManual = false,
  int manualLayers = 30,
  KoboldGpuBackend backend = KoboldGpuBackend.cuda,
  bool rocm = false,
  bool flashAttention = true,
  KvQuant kvQuant = KvQuant.f16,
  bool mlock = false,
  int contextSize = 16384,
  ContextManagementMode contextMode =
      ContextManagementMode.fastForwardSmartCache,
}) => KoboldAppSettings(
  contextSize: contextSize,
  batchSize: 512,
  layersManual: layersManual,
  manualLayers: manualLayers,
  backend: backend,
  gpuId: 0,
  rocm: rocm,
  flashAttention: flashAttention,
  kvQuant: kvQuant,
  mlock: mlock,
  contextMode: contextMode,
);

Map<String, dynamic> _map(
  KoboldAppSettings settings, {
  KoboldModelFacts model = const KoboldModelFacts(),
}) => kcppsMap(
  koboldAppConfig(modelPath: '/m/a.gguf', settings: settings, model: model),
);

void main() {
  test('by default KoboldCpp fits the model: automatic layers, no lock, '
      'no forced fit', () {
    final map = _map(_settings());
    expect(map['gpulayers'], -1);
    expect(map['usemlock'], isFalse);
    expect(map.containsKey('autofit'), isFalse);
    expect(map.containsKey('moecpu'), isFalse);
  });

  test('the context size the user asked for is never resized', () {
    expect(_map(_settings(contextSize: 32768))['contextsize'], 32768);
    expect(_map(_settings(contextSize: 2048))['contextsize'], 2048);
  });

  test('a manual layer count is written as given', () {
    expect(
      _map(_settings(layersManual: true, manualLayers: 20))['gpulayers'],
      20,
    );
    // 0 is a real choice: keep the model off the card.
    expect(
      _map(_settings(layersManual: true, manualLayers: 0))['gpulayers'],
      0,
    );
  });

  group('a MoE model', () {
    const moe = KoboldModelFacts(isMoe: true);

    test('on automatic layers is left entirely to KoboldCpp', () {
      final map = _map(_settings(mlock: true), model: moe);
      expect(map['gpulayers'], -1);
      expect(map.containsKey('moecpu'), isFalse);
      expect(map['usemlock'], isFalse);
    });

    test('with a manual layer count keeps its experts in system memory and '
        'is never locked there', () {
      final map = _map(
        _settings(layersManual: true, manualLayers: 30, mlock: true),
        model: moe,
      );
      expect(map['gpulayers'], 30);
      expect(map['moecpu'], 999);
      expect(map['usemlock'], isFalse);
    });

    test('on Apple Silicon is not split: system and graphics memory are '
        'one pool', () {
      final map = _map(
        _settings(layersManual: true),
        model: const KoboldModelFacts(isMoe: true, expertsShareGpuMemory: true),
      );
      expect(map.containsKey('moecpu'), isFalse);
    });
  });

  test('the memory lock needs both the setting and a manual layer count', () {
    expect(_map(_settings(mlock: true))['usemlock'], isFalse);
    expect(
      _map(_settings(mlock: true, layersManual: true))['usemlock'],
      isTrue,
    );
    expect(_map(_settings(layersManual: true))['usemlock'], isFalse);
  });

  test('sliding window is applied only to a model that has it, and then '
      'always with fast forward off', () {
    final wanted = _settings(
      contextMode: ContextManagementMode.slidingWindowAttention,
    );
    final without = _map(wanted);
    expect(without['noswa'], isTrue);
    expect(without['nofastforward'], isFalse);

    final has = _map(
      wanted,
      model: const KoboldModelFacts(hasSlidingWindow: true),
    );
    expect(has['noswa'], isFalse);
    expect(has['nofastforward'], isTrue);
    expect(has['noshift'], isTrue);
  });

  test('a model with sliding window still defaults to it off, with fast '
      'forward on', () {
    final map = _map(
      _settings(),
      model: const KoboldModelFacts(hasSlidingWindow: true),
    );
    expect(map['noswa'], isTrue);
    expect(map['nofastforward'], isFalse);
    expect(map['noshift'], isFalse);
  });

  test('a compressed cache turns flash attention on; ROCm never has it', () {
    expect(_map(_settings(flashAttention: false))['noflashattention'], isTrue);
    expect(
      _map(
        _settings(flashAttention: false, kvQuant: KvQuant.q5_1),
      )['noflashattention'],
      isFalse,
    );
    // bf16 is the same size as f16: nothing to make it need flash attention.
    expect(
      _map(
        _settings(flashAttention: false, kvQuant: KvQuant.bf16),
      )['noflashattention'],
      isTrue,
    );
    expect(
      _map(_settings(rocm: true, kvQuant: KvQuant.q4_0))['noflashattention'],
      isTrue,
    );
  });
}
