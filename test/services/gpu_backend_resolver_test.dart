// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/gpu_backend_resolver.dart';

void main() {
  GpuBackend resolve({
    bool? cublas,
    bool? vulkan,
    bool? rocm,
    bool? metal,
    bool hasCuda = false,
    String vendor = 'Unknown',
  }) => GpuBackendResolver.resolve(
    userCublas: cublas,
    userVulkan: vulkan,
    userRocm: rocm,
    userMetal: metal,
    hasCuda: hasCuda,
    vendor: vendor,
  );

  group(
    'automatic resolution (all prefs null)',
    () {
      test('NVIDIA with driver → CUDA', () {
        expect(resolve(hasCuda: true, vendor: 'Nvidia'), GpuBackend.cuda);
      });
      test('AMD → Vulkan, NEVER ROCm', () {
        expect(resolve(vendor: 'AMD'), GpuBackend.vulkan);
      });
      test('Intel → Vulkan', () {
        expect(resolve(vendor: 'Intel'), GpuBackend.vulkan);
      });
      test('no usable GPU → CPU', () {
        expect(resolve(vendor: 'Unknown'), GpuBackend.cpu);
      });
    },
    skip: Platform.isMacOS ? 'auto resolves to Metal on macOS' : false,
  );

  group('user overrides win', () {
    test('explicit ROCm beats everything', () {
      expect(
        resolve(rocm: true, hasCuda: true, vendor: 'Nvidia'),
        GpuBackend.rocm,
      );
    });
    test('explicit all-false is CPU-only', () {
      expect(
        resolve(
          cublas: false,
          vulkan: false,
          rocm: false,
          metal: false,
          hasCuda: true,
          vendor: 'Nvidia',
        ),
        GpuBackend.cpu,
      );
    });
    test('isAutomatic only when nothing was ever set', () {
      expect(
        GpuBackendResolver.isAutomatic(
          userCublas: null,
          userVulkan: null,
          userRocm: null,
          userMetal: null,
        ),
        isTrue,
      );
      expect(
        GpuBackendResolver.isAutomatic(
          userCublas: null,
          userVulkan: false,
          userRocm: null,
          userMetal: null,
        ),
        isFalse,
      );
    });
  });

  group('HSA override mapping', () {
    test('officially supported archs need no override', () {
      for (final gfx in ['gfx900', 'gfx906', 'gfx90a', 'gfx1030', 'gfx1100']) {
        expect(GpuBackendResolver.hsaOverrideForGfx(gfx), isNull, reason: gfx);
      }
    });
    test('consumer RDNA2 → 10.3.0', () {
      for (final gfx in ['gfx1031', 'gfx1032', 'gfx1034', 'gfx1035']) {
        expect(
          GpuBackendResolver.hsaOverrideForGfx(gfx),
          '10.3.0',
          reason: gfx,
        );
      }
    });
    test('consumer RDNA3 → 11.0.0', () {
      for (final gfx in ['gfx1101', 'gfx1102', 'gfx1103', 'gfx1150']) {
        expect(
          GpuBackendResolver.hsaOverrideForGfx(gfx),
          '11.0.0',
          reason: gfx,
        );
      }
    });
    test('unknown or non-gfx input → no guess', () {
      expect(GpuBackendResolver.hsaOverrideForGfx('gfx803'), isNull);
      expect(GpuBackendResolver.hsaOverrideForGfx('cpu'), isNull);
      expect(GpuBackendResolver.hsaOverrideForGfx(''), isNull);
    });
  });

  test('gfxFromRocminfo yields a family-correct arch on APU+dGPU', () {
    const output = '''
Agent 1
  Name:                    AMD Ryzen 7 7840HS
  Device Type:             CPU
Agent 2
  Name:                    gfx1103
  Marketing Name:          AMD Radeon 780M
  Device Type:             GPU
Agent 3
  Name:                    gfx1100
  Marketing Name:          AMD Radeon RX 7900 XTX
  Device Type:             GPU
''';
    expect(GpuBackendResolver.gfxFromRocminfo(output), 'gfx1103');
    // NOTE: sorted-last picks the highest gfx number. gfx1103 (iGPU) sorts
    // above gfx1100 (dGPU) — both are RDNA3 and map to the same 11.0.0
    // override, so the launch env is correct either way; the officially
    // supported-arch check runs on the same pick.
    expect(
      GpuBackendResolver.hsaOverrideForGfx(
        GpuBackendResolver.gfxFromRocminfo(output)!,
      ),
      '11.0.0',
    );
    expect(GpuBackendResolver.gfxFromRocminfo('no gpus here'), isNull);
  });
}
