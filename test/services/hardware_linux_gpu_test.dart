// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The graphics card read from the Linux driver's own files, laid out here the
// way the maintainer's RX 6900 XT machine has them (values copied from it):
// /sys/class/drm/card0 and renderD128 (one card, two names), the card's
// vendor, device and revision ids and memory, libdrm's amdgpu.ids, /dev/kfd
// and the KFD topology (node 0 the processor, node 1 the card). It must find
// the card by name with its memory with or without lspci installed, and
// Automatic must give it the graphics card, not the processor.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/gpu_backend_resolver.dart';
import 'package:front_porch_ai/services/services.dart';

const _lspci =
    '2f:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] '
    'Navi 21 [Radeon RX 6900 XT] (rev c0)\n';

const _vramBytes = 17163091968; // mem_info_vram_total on that card

void main() {
  late Directory root;
  late LinuxGpuPaths paths;

  Future<void> write(String path, String text) async {
    final f = File(p.join(root.path, path));
    await f.parent.create(recursive: true);
    await f.writeAsString(text);
  }

  Future<void> card(String name) async {
    await write('drm/$name/device/vendor', '0x1002\n');
    await write('drm/$name/device/device', '0x73af\n');
    await write('drm/$name/device/revision', '0xc0\n');
    await write('drm/$name/device/mem_info_vram_total', '$_vramBytes\n');
    await write('drm/$name/device/mem_info_vram_used', '27652096\n');
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fpai linux gpu');
    await card('card0');
    await card('renderD128');
    await Directory(p.join(root.path, 'drm', 'card0-DP-1')).create();
    await write('drm/version', '1.1.0\n');
    await write(
      'amdgpu.ids',
      '# List of AMDGPU IDs\n#\n1.0.0\n'
          '73A5,\tC0,\tAMD Radeon RX 6950 XT\n'
          '73AF,\tC0,\tAMD Radeon RX 6900 XT\n',
    );
    await write('dev/kfd', '');
    await write(
      'kfd/0/properties',
      'cpu_cores_count 16\nsimd_count 0\ngfx_target_version 0\n'
          'vendor_id 0\ndevice_id 0\n',
    );
    await write(
      'kfd/1/properties',
      'cpu_cores_count 0\nsimd_count 160\ngfx_target_version 100300\n'
          'vendor_id 4098\ndevice_id 29615\ndrm_render_minor 128\n',
    );
    paths = LinuxGpuPaths(
      drm: p.join(root.path, 'drm'),
      kfdDevice: p.join(root.path, 'dev', 'kfd'),
      amdgpuIds: p.join(root.path, 'amdgpu.ids'),
    );
  });

  tearDown(() => root.delete(recursive: true));

  test('without lspci: the card by name, with its memory, once', () async {
    final gpu = await readLinuxGpu(paths: paths);
    expect(gpu.vendor, 'AMD');
    expect(gpu.name, 'AMD Radeon RX 6900 XT');
    expect(gpu.vramMb, 16368);
    expect(gpu.cardCount, 1, reason: 'card0 and renderD128 are one card');
    expect(gpu.hasKfd, isTrue);
  });

  test('with lspci: the same card', () async {
    final gpu = await readLinuxGpu(lspci: _lspci, paths: paths);
    expect(
      (gpu.vendor, gpu.name, gpu.vramMb),
      ('AMD', 'AMD Radeon RX 6900 XT', 16368),
    );
  });

  test(
    'without lspci or libdrm\'s names: still an AMD card with its memory',
    () async {
      await File(paths.amdgpuIds).delete();
      final gpu = await readLinuxGpu(paths: paths);
      expect(
        (gpu.vendor, gpu.name, gpu.vramMb),
        ('AMD', 'AMD graphics card', 16368),
      );
    },
  );

  test(
    'the compute device is a character device, and counts as there',
    () async {
      // /dev/kfd is a character device. Dart's FileSystemEntity.type calls
      // one "notFound" (seen on the real machine); /dev/null is one on
      // every POSIX runner.
      final gpu = await readLinuxGpu(
        paths: LinuxGpuPaths(
          drm: paths.drm,
          kfdDevice: '/dev/null',
          amdgpuIds: paths.amdgpuIds,
        ),
      );
      expect(gpu.hasKfd, isTrue);
    },
    skip: Platform.isWindows ? 'no character devices' : false,
  );

  test('no compute device: no ROCm', () async {
    await File(paths.kfdDevice).delete();
    expect((await readLinuxGpu(paths: paths)).hasKfd, isFalse);
  });

  test('Automatic on this card is Vulkan, not CPU only', () async {
    final gpu = await readLinuxGpu(lspci: _lspci, paths: paths);
    expect(
      GpuBackendResolver.resolve(
        userCublas: null,
        userVulkan: null,
        userRocm: null,
        userMetal: null,
        hasCuda: false,
        vendor: gpu.vendor,
        onMac: false,
      ),
      GpuBackend.vulkan,
    );
  });

  test(
    'the ROCm arch comes from the topology when rocminfo is absent',
    () async {
      final gfx = await GpuBackendResolver.gfxFromKfdTopology(
        p.join(root.path, 'kfd'),
      );
      expect(gfx, 'gfx1030');
      expect(
        GpuBackendResolver.hsaOverrideForGfx(gfx!),
        isNull,
        reason: 'gfx1030 needs no override',
      );
      await write(
        'kfd/1/properties',
        'gfx_target_version 100301\nvendor_id 4098\n',
      );
      final rx6700 = await GpuBackendResolver.gfxFromKfdTopology(
        p.join(root.path, 'kfd'),
      );
      expect(rx6700, 'gfx1031');
      expect(GpuBackendResolver.hsaOverrideForGfx(rx6700!), '10.3.0');
    },
  );

  test(
    'this account\'s access to the compute device is read',
    () async {
      final kfd = paths.kfdDevice;
      expect(await kfdAccessible(kfd), isTrue);
      await Process.run('chmod', ['000', kfd]);
      expect(await kfdAccessible(kfd), isFalse);
    },
    skip: Platform.isWindows || _isRoot()
        ? 'needs a non-root POSIX shell'
        : false,
  );
}

bool _isRoot() => !Platform.isWindows && Platform.environment['USER'] == 'root';
