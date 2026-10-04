// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// When the app writes flash attention off. Seen on real engines on
// 2026-10-04: KoboldCpp 1.122.1 on Vulkan (RX 6900 XT) loads Gemma 4 and
// dies on its first prompt with flash attention on, and runs it with it
// off; the ROCm build ran every model tested with it on. The maintainer
// ruled: Gemma 4 on Vulkan gets it off, in the app's own launches and in
// generated presets; ROCm gets it, unless it already died there.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';

KoboldLaunchConfig _auto({
  required KoboldGpuBackend backend,
  String? architecture,
  KvQuant kvQuant = KvQuant.q8_0,
}) => koboldAppConfig(
  modelPath: '/m/a.gguf',
  settings: KoboldAppSettings(
    contextSize: 16384,
    batchSize: 512,
    layersManual: false,
    manualLayers: 0,
    backend: backend,
    gpuId: 0,
    rocm: false,
    flashAttention: true,
    kvQuant: kvQuant,
    mlock: false,
    contextMode: ContextManagementMode.fastForwardSmartCache,
  ),
  model: KoboldModelFacts(architecture: architecture),
);

KoboldLaunchConfig _generated({
  required KoboldGpuBackend backend,
  String? architecture,
}) => koboldGeneratedPreset(
  modelPath: '/m/a.gguf',
  contextSize: 16384,
  batchSize: 512,
  threads: 8,
  greedyAllocation: false,
  kvQuant: KvQuant.q8_0,
  backend: backend,
  gpuId: null,
  contextMode: ContextManagementMode.fastForwardSmartCache,
  smartCacheSlots: 0,
  architecture: architecture,
);

void main() {
  test('Gemma 4 on Vulkan: flash attention off, and the cache full size '
      'since compression needs it', () {
    for (final config in [
      _auto(backend: KoboldGpuBackend.vulkan, architecture: 'gemma4'),
      _generated(backend: KoboldGpuBackend.vulkan, architecture: 'gemma4'),
    ]) {
      final map = kcppsMap(config);
      expect(map['noflashattention'], isTrue);
      expect(map['quantkv'], 'f16');
    }
  });

  test('Gemma 4 elsewhere, and other models on Vulkan, keep flash attention '
      'and their compressed cache', () {
    for (final config in [
      _auto(backend: KoboldGpuBackend.cuda, architecture: 'gemma4'),
      _auto(backend: KoboldGpuBackend.vulkan, architecture: 'gemma3'),
      _generated(backend: KoboldGpuBackend.cuda, architecture: 'gemma4'),
      _generated(backend: KoboldGpuBackend.vulkan, architecture: 'qwen3'),
    ]) {
      final map = kcppsMap(config);
      expect(map['noflashattention'], isFalse);
      expect(map['quantkv'], 'q8_0');
    }
  });

  test('the launch says why, in plain words', () {
    expect(
      koboldFlashAttentionNote(
        backend: KoboldGpuBackend.vulkan,
        rocm: false,
        architecture: 'gemma4',
      ),
      contains('Gemma 4 on Vulkan'),
    );
    expect(
      koboldFlashAttentionNote(
        backend: KoboldGpuBackend.cuda,
        rocm: true,
        rocmFailedBefore: true,
      ),
      contains('stopped on this machine'),
    );
    expect(
      koboldFlashAttentionNote(backend: KoboldGpuBackend.cuda, rocm: true),
      isNull,
    );
  });
}
