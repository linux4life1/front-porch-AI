// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The preset the "Generate preset" dialog writes. Its VRAM estimate counts
// on the graphics memory the fit leaves spare (1024 MB, or 32 MB with
// "Greedy memory allocation"), so the preset must carry that padding and
// force the fit: KoboldCpp keeps a preset's padding only when the fit is
// forced. Switching the fit on by itself, it puts the padding back to 1024.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';

KoboldLaunchConfig _preset({bool greedy = false}) => koboldGeneratedPreset(
  modelPath: '/m/a.gguf',
  contextSize: 16384,
  batchSize: 512,
  threads: 8,
  greedyAllocation: greedy,
  kvQuant: KvQuant.f16,
  backend: KoboldGpuBackend.cuda,
  gpuId: 0,
  contextMode: ContextManagementMode.fastForwardSmartCache,
  smartCacheSlots: 0,
);

void main() {
  test('the preset forces the fit and carries the padding the estimate '
      'counted on', () {
    final normal = kcppsMap(_preset());
    expect(normal['gpulayers'], -1);
    expect(normal['autofit'], isTrue);
    expect(normal['autofitpadding'], koboldAutofitPaddingMb(greedy: false));

    final greedy = kcppsMap(_preset(greedy: true));
    expect(greedy['autofit'], isTrue);
    expect(greedy['autofitpadding'], koboldAutofitPaddingMb(greedy: true));
  });

  test('changing a setting on the preset keeps the forced fit', () {
    final edited = _preset(
      greedy: true,
    ).copyWith(contextSize: 32768, kvQuant: KvQuant.q8_0);
    final map = kcppsMap(edited);
    expect(map['contextsize'], 32768);
    expect(map['autofit'], isTrue);
    expect(map['autofitpadding'], 32);
  });

  test('the padding is 1024 MB, or 32 MB when greedy', () {
    expect(koboldAutofitPaddingMb(greedy: false), 1024);
    expect(koboldAutofitPaddingMb(greedy: true), 32);
  });
}
