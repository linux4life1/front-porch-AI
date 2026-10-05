// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The one rule for which graphics backend KoboldCpp runs and which memory
// rules the estimate judges it by. A launch, the Local model card (desktop
// and phone) and the preset editor all ask it, so each case here is a
// machine and a set of switches and what the answer must be for all of them.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/hardware_info.dart';
import 'package:front_porch_ai/services/gpu_backend_resolver.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/utils/kobold_memory_rules.dart';

HardwareInfo _hw(String vendor, {bool cuda = false, bool metal = false}) =>
    HardwareInfo(
      gpuName: '$vendor card',
      vramMb: 8192,
      ramMb: 32768,
      vendor: vendor,
      hasCuda: cuda,
      hasMetal: metal,
    );

final _nvidia = _hw('Nvidia', cuda: true);
final _amd = _hw('AMD');
final _intel = _hw('Intel');
final _unknown = _hw('Unknown');
final _apple = _hw('Apple', metal: true);

/// What the choice says, as plain values.
typedef _Says = ({
  KoboldGpuBackend backend,
  int? gpuId,
  bool rocm,
  KoboldMemoryBackend memory,
  bool onCard,
});

_Says _says(KoboldBackendChoice c) => (
  backend: c.backend,
  gpuId: c.gpuId,
  rocm: c.rocm,
  memory: c.memory,
  onCard: c.onCard,
);

_Says _expect(
  KoboldGpuBackend backend,
  KoboldMemoryBackend memory, {
  int? gpuId,
  bool rocm = false,
  bool onCard = true,
}) => (
  backend: backend,
  gpuId: gpuId,
  rocm: rocm,
  memory: memory,
  onCard: onCard,
);

void main() {
  group('from the switches in Settings', () {
    test('with none chosen, the detected card decides', () {
      expect(
        _says(koboldBackendFor(hardware: _nvidia, gpuId: 1)),
        _expect(KoboldGpuBackend.cuda, KoboldMemoryBackend.cuda, gpuId: 1),
      );
      for (final amd in [_amd, _intel]) {
        expect(
          _says(koboldBackendFor(hardware: amd)),
          _expect(KoboldGpuBackend.vulkan, KoboldMemoryBackend.vulkan),
        );
      }
      // Nothing KoboldCpp could use: no card, and no pretence of one.
      expect(
        _says(koboldBackendFor(hardware: _unknown)),
        _expect(KoboldGpuBackend.none, KoboldMemoryBackend.cuda, onCard: false),
      );
    });

    test('Apple hardware is one pool of memory whatever the switches say', () {
      for (final switches in <(bool?, bool?, bool?, bool?)>[
        (null, null, null, null),
        (false, false, false, false),
        (false, false, false, true),
      ]) {
        final c = koboldBackendFor(
          hardware: _apple,
          cublas: switches.$1,
          vulkan: switches.$2,
          rocm: switches.$3,
          metal: switches.$4,
        );
        expect(c.backend, KoboldGpuBackend.none, reason: '$switches');
        expect(c.memory, KoboldMemoryBackend.metal, reason: '$switches');
        expect(c.onCard, isTrue, reason: '$switches');
      }
    });

    test('a backend chosen in Settings is the one that runs, on any card', () {
      // The chips write all four switches: the chosen one on, the rest off.
      expect(
        _says(
          koboldBackendFor(
            hardware: _amd,
            cublas: false,
            vulkan: false,
            rocm: true,
            metal: false,
            gpuId: 2,
          ),
        ),
        _expect(
          KoboldGpuBackend.cuda,
          KoboldMemoryBackend.rocm,
          gpuId: 2,
          rocm: true,
        ),
        reason: 'ROCm on an AMD card is judged by ROCm, not by Vulkan',
      );
      expect(
        _says(
          koboldBackendFor(
            hardware: _nvidia,
            cublas: false,
            vulkan: true,
            rocm: false,
            metal: false,
          ),
        ),
        _expect(KoboldGpuBackend.vulkan, KoboldMemoryBackend.vulkan),
        reason: 'Vulkan on an NVIDIA card is not CUDA',
      );
      expect(
        _says(
          koboldBackendFor(
            hardware: _amd,
            cublas: true,
            vulkan: false,
            rocm: false,
            metal: false,
          ),
        ),
        _expect(KoboldGpuBackend.cuda, KoboldMemoryBackend.cuda, gpuId: 0),
      );
    });

    test('"CPU only" is every switch off, and puts nothing on a card', () {
      final c = koboldBackendFor(
        hardware: _nvidia,
        cublas: false,
        vulkan: false,
        rocm: false,
        metal: false,
      );
      expect(c.backend, KoboldGpuBackend.none);
      expect(c.onCard, isFalse);
      expect(c.rocm, isFalse);
    });

    test('a switch that was never touched is not "off": some chosen off and '
        'the rest never chosen is automatic, as Settings shows it', () {
      final c = koboldBackendFor(hardware: _nvidia, cublas: false);
      expect(c.backend, KoboldGpuBackend.cuda);
      expect(
        GpuBackendResolver.resolve(
          userCublas: false,
          userVulkan: null,
          userRocm: null,
          userMetal: null,
          hasCuda: true,
          vendor: 'Nvidia',
          onMac: false,
        ),
        GpuBackend.cuda,
        reason: 'the Settings status line says the same',
      );
    });

    test('with the machine not detected yet, a chosen backend still holds', () {
      final c = koboldBackendFor(hardware: null, rocm: true, unified: false);
      expect(c.rocm, isTrue);
      expect(c.backend, KoboldGpuBackend.cuda);
      expect(
        koboldBackendFor(hardware: null, unified: false).backend,
        KoboldGpuBackend.none,
      );
    });

    test('the caller can say whether the machine is Apple hardware', () {
      // A test machine that is a Mac pretending to be a PC, and the other
      // way round, must not be read as the one it runs on.
      expect(
        koboldBackendFor(hardware: _nvidia, unified: false).backend,
        KoboldGpuBackend.cuda,
      );
      expect(
        koboldBackendFor(hardware: _nvidia, unified: true).unified,
        isTrue,
      );
    });
  });

  group('a preset names its own backend', () {
    test('the switches do not override it; they only say it is ROCm', () {
      final vulkan = koboldBackendFor(
        hardware: _nvidia,
        rocm: false,
        unified: false,
        preset: KoboldGpuBackend.vulkan,
        presetGpuId: 1,
      );
      expect(
        _says(vulkan),
        _expect(KoboldGpuBackend.vulkan, KoboldMemoryBackend.vulkan, gpuId: 1),
      );
      final rocm = koboldBackendFor(
        hardware: _amd,
        rocm: true,
        unified: false,
        preset: KoboldGpuBackend.cuda,
        presetGpuId: 0,
      );
      expect(
        _says(rocm),
        _expect(
          KoboldGpuBackend.cuda,
          KoboldMemoryBackend.rocm,
          gpuId: 0,
          rocm: true,
        ),
      );
      final none = koboldBackendFor(
        hardware: _nvidia,
        unified: false,
        preset: KoboldGpuBackend.none,
      );
      expect(none.onCard, isFalse);
      expect(
        koboldBackendFor(
          hardware: _apple,
          preset: KoboldGpuBackend.none,
        ).onCard,
        isTrue,
        reason: 'Apple hardware always has its memory to put the model in',
      );
    });
  });

  group('the machine a model is fitted to', () {
    test('free graphics memory is the first card\'s, and each further card '
        'counts as the smallest, less the half a GB it keeps', () {
      final two = HardwareInfo(
        gpuName: 'two cards',
        vramMb: 12288,
        ramMb: 32768,
        vendor: 'Nvidia',
        hasCuda: true,
        cardCount: 2,
        smallestCardMb: 8192,
      );
      final choice = koboldBackendFor(hardware: two, unified: false);
      final one = choice.machineFor(two, (graphics: 10000, system: 20000));
      expect(one.totalGraphicsMb, 12288);
      expect(one.freeGraphicsMb, 10000);
      expect(one.freeSystemMb, 20000);
      final both = choice.machineFor(two, (
        graphics: 10000,
        system: 20000,
      ), cards: 2);
      expect(both.totalGraphicsMb, 12288 + 8192);
      expect(both.freeGraphicsMb, 10000 + 8192 - 512);
    });

    test('without a card there is no graphics memory, free or total', () {
      final cpu = koboldBackendFor(
        hardware: _nvidia,
        cublas: false,
        vulkan: false,
        rocm: false,
        metal: false,
      ).machineFor(_nvidia, (graphics: 7000, system: 20000));
      expect(cpu.totalGraphicsMb, 0);
      expect(cpu.freeGraphicsMb, 0);
      expect(cpu.freeSystemMb, 20000);
    });

    test('the batch is KoboldCpp\'s own with no card, else the user\'s '
        'choice, else left to the tuning', () {
      final card = koboldBackendFor(hardware: _nvidia);
      final cpu = koboldBackendFor(
        hardware: _nvidia,
        cublas: false,
        vulkan: false,
        rocm: false,
        metal: false,
      );
      expect(card.fixedBatch(automatic: true, chosen: 4096), isNull);
      expect(card.fixedBatch(automatic: false, chosen: 4096), 4096);
      expect(cpu.fixedBatch(automatic: false, chosen: 4096), 512);
      expect(cpu.fixedBatch(automatic: true, chosen: 4096), 512);
    });
  });
}
