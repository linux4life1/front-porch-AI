// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Flash attention and a compressed chat memory: one rule for every config
// the app writes (maintainer, 2026-10-05). Auto mode always turned flash
// attention on for a compressed cache, since the cache needs it. The preset
// editor did the opposite with the same settings: flash attention off meant
// a full-size cache, so a preset made "from my settings" used more memory
// than the automatic launch it copied. Now both builders take the pair from
// koboldFlashAndCache: a compressed cache turns flash attention on wherever
// it can run, and where it cannot (Gemma 4 on Vulkan, a ROCm machine where
// it died) flash attention is off and the cache full size.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';

void main() {
  test('a compressed cache turns flash attention on; a full one keeps the '
      'switch; where it cannot run, the cache is full size', () {
    for (final (runs, flash, cache, wantFlash, wantCache) in [
      (true, false, KvQuant.q8_0, true, KvQuant.q8_0),
      (true, false, KvQuant.q5_1, true, KvQuant.q5_1),
      (true, false, KvQuant.q4_0, true, KvQuant.q4_0),
      (true, true, KvQuant.q8_0, true, KvQuant.q8_0),
      (true, false, KvQuant.f16, false, KvQuant.f16),
      (true, true, KvQuant.f16, true, KvQuant.f16),
      // bf16 is the same size as f16: nothing to turn on.
      (true, false, KvQuant.bf16, false, KvQuant.bf16),
      (false, true, KvQuant.q8_0, false, KvQuant.f16),
      (false, false, KvQuant.q4_0, false, KvQuant.f16),
      (false, true, KvQuant.f16, false, KvQuant.f16),
    ]) {
      final pair = koboldFlashAndCache(
        runs: runs,
        flashAttention: flash,
        kvQuant: cache,
      );
      final asked = 'runs $runs, flash $flash, ${cache.wire}';
      expect(pair.flashAttention, wantFlash, reason: asked);
      expect(pair.kvQuant, wantCache, reason: asked);
    }
  });

  test('the preset the editor writes runs the pair auto mode launches, for '
      'every backend, model and setting', () {
    const archs = ['qwen3', 'gemma4'];
    final backends = [KoboldGpuBackend.cuda, KoboldGpuBackend.vulkan];
    for (final backend in backends) {
      for (final rocm in [false, true]) {
        if (rocm && backend != KoboldGpuBackend.cuda) continue;
        for (final failed in [false, true]) {
          for (final arch in archs) {
            for (final flash in [false, true]) {
              for (final cache in KvQuant.values) {
                final auto = kcppsMap(
                  koboldAppConfig(
                    modelPath: '/m/a.gguf',
                    settings: KoboldAppSettings(
                      contextSize: 16384,
                      batchSize: 512,
                      layersManual: false,
                      manualLayers: 0,
                      backend: backend,
                      gpuId: 0,
                      rocm: rocm,
                      flashAttention: flash,
                      kvQuant: cache,
                      mlock: false,
                      rocmFlashAttentionFailed: failed,
                    ),
                    model: KoboldModelFacts(architecture: arch),
                  ),
                );
                final preset = kcppsMap(
                  koboldGeneratedPreset(
                    modelPath: '/m/a.gguf',
                    contextSize: 16384,
                    batchSize: 512,
                    threads: 8,
                    greedyAllocation: false,
                    kvQuant: cache,
                    backend: backend,
                    gpuId: 0,
                    contextMode: ContextManagementMode.fastForwardSmartCache,
                    smartCacheSlots: 0,
                    architecture: arch,
                    flashAttention: flash,
                    rocm: rocm,
                    rocmFlashAttentionFailed: failed,
                  ),
                );
                final asked =
                    '${backend.name}${rocm ? ' (ROCm)' : ''}, $arch, '
                    'flash $flash, ${cache.wire}, died before $failed';
                expect(
                  preset['noflashattention'],
                  auto['noflashattention'],
                  reason: asked,
                );
                expect(preset['quantkv'], auto['quantkv'], reason: asked);
              }
            }
          }
        }
      }
    }
  });

  test('flash attention switched off with an 8-bit cache: the preset keeps '
      'the 8-bit cache and runs flash attention', () {
    final map = kcppsMap(
      koboldGeneratedPreset(
        modelPath: '/m/a.gguf',
        contextSize: 16384,
        batchSize: 512,
        threads: 8,
        greedyAllocation: false,
        kvQuant: KvQuant.q8_0,
        backend: KoboldGpuBackend.cuda,
        gpuId: 0,
        contextMode: ContextManagementMode.fastForwardSmartCache,
        smartCacheSlots: 0,
        architecture: 'qwen3',
        flashAttention: false,
      ),
    );

    expect(map['noflashattention'], isFalse);
    expect(map['quantkv'], 'q8_0');
  });
}
