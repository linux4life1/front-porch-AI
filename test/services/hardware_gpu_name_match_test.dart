// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for cross-source GPU name matching on Windows (issue #137).
//
// The regression these lock down: shared-memory detection compared WMI's
// adapter name to the registry/nvidia-smi name with `==`. On AMD APUs the two
// spellings differ, the match failed, VRAM stayed 0, and KoboldLayerSolver
// turned that into `--gpulayers 0` — a silent CPU-only launch.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/hardware_service.dart';

void main() {
  group('HardwareService.gpuNamesMatch', () {
    test('matches the AMD APU spellings that broke issue #137', () {
      // Registry DriverDesc vs WMI Win32_VideoController.Name on a Ryzen APU.
      expect(
        HardwareService.gpuNamesMatch(
          'AMD Radeon(TM) 780M Graphics',
          'AMD Radeon(TM) Graphics',
        ),
        isTrue,
      );
    });

    test('is symmetric', () {
      expect(
        HardwareService.gpuNamesMatch(
          'AMD Radeon(TM) Graphics',
          'AMD Radeon(TM) 780M Graphics',
        ),
        isTrue,
      );
    });

    test('matches identical names', () {
      expect(
        HardwareService.gpuNamesMatch(
          'NVIDIA GeForce RTX 5060 Ti',
          'NVIDIA GeForce RTX 5060 Ti',
        ),
        isTrue,
      );
    });

    test('ignores trademark noise and punctuation differences', () {
      expect(
        HardwareService.gpuNamesMatch(
          'Intel(R) Arc(TM) A770 Graphics',
          'Intel Arc A770 Graphics',
        ),
        isTrue,
      );
    });

    test('does NOT match a discrete AMD card against an AMD iGPU', () {
      // The dangerous false positive: on a laptop with both, letting the iGPU
      // claim the discrete card's slot would overwrite real VRAM with a
      // shared-memory figure.
      expect(
        HardwareService.gpuNamesMatch(
          'AMD Radeon RX 7900 XTX',
          'AMD Radeon(TM) Graphics',
        ),
        isFalse,
      );
    });

    test('does not match across vendors', () {
      expect(
        HardwareService.gpuNamesMatch(
          'NVIDIA GeForce RTX 4060',
          'AMD Radeon(TM) Graphics',
        ),
        isFalse,
      );
    });

    test('a single shared vendor token is not enough', () {
      expect(HardwareService.gpuNamesMatch('AMD', 'AMD Radeon Graphics'), isFalse);
      expect(HardwareService.gpuNamesMatch('Intel', 'Intel Arc A770'), isFalse);
    });

    test('empty or unknown names never match', () {
      expect(HardwareService.gpuNamesMatch('', 'AMD Radeon Graphics'), isFalse);
      expect(HardwareService.gpuNamesMatch('AMD Radeon Graphics', ''), isFalse);
      expect(
        HardwareService.gpuNamesMatch('Unknown GPU', 'AMD Radeon(TM) Graphics'),
        isFalse,
      );
    });

    test('distinguishes two discrete cards from the same vendor', () {
      expect(
        HardwareService.gpuNamesMatch(
          'NVIDIA GeForce RTX 4060',
          'NVIDIA GeForce RTX 4090',
        ),
        isFalse,
      );
    });
  });
}
