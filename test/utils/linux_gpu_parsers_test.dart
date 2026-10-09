// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The graphics card read from what Linux's own tools and driver files print.
// The AMD lines are this app's maintainer's RX 6900 XT as lspci and the
// driver print them; the others are the same tools' lines for an NVIDIA
// laptop with Intel graphics and two Intel-only machines. The old reader
// cut the AMD line at the colon inside "2f:00.0" and dropped every bracket,
// which threw away "AMD/ATI" and "Radeon": the card came out Unknown.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/utils/utils.dart';

const _amd =
    '00:00.0 Host bridge: Advanced Micro Devices, Inc. [AMD] Starship/Matisse '
    'Root Complex\n'
    '2f:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] '
    'Navi 21 [Radeon RX 6900 XT] (rev c0)\n'
    '2f:00.1 Audio device: Advanced Micro Devices, Inc. [AMD/ATI] Navi 21/23 '
    'HDMI/DP Audio Controller\n';

const _amdNumeric =
    '2f:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. '
    '[AMD/ATI] Navi 21 [Radeon RX 6900 XT] [1002:73af] (rev c0)\n';

const _nvidiaLaptop =
    '00:02.0 VGA compatible controller: Intel Corporation Alder Lake-P GT2 '
    '[Iris Xe Graphics] (rev 0c)\n'
    '01:00.0 3D controller: NVIDIA Corporation GA107M [GeForce RTX 3050 '
    'Mobile] (rev a1)\n';

const _intelOnly =
    '00:02.0 VGA compatible controller: Intel Corporation CometLake-U GT2 '
    '[UHD Graphics] (rev 02)\n';

const _noBrackets =
    '00:02.0 VGA compatible controller: Intel Corporation HD Graphics 620 '
    '(rev 02)\n';

void main() {
  group('lspci', () {
    test('this machine\'s AMD card keeps its vendor and marketing name', () {
      expect(lspciGpu(_amd), (name: 'AMD Radeon RX 6900 XT', vendor: 'AMD'));
      expect(lspciGpu(_amdNumeric), (
        name: 'AMD Radeon RX 6900 XT',
        vendor: 'AMD',
      ), reason: 'lspci -nn adds the class and the ids');
    });

    test('a laptop\'s NVIDIA "3D controller" wins over its Intel graphics', () {
      expect(lspciGpu(_nvidiaLaptop), (
        name: 'NVIDIA GeForce RTX 3050 Mobile',
        vendor: 'Nvidia',
      ));
    });

    test('an Intel-only machine, with and without a bracketed name', () {
      expect(lspciGpu(_intelOnly), (
        name: 'Intel UHD Graphics',
        vendor: 'Intel',
      ));
      expect(lspciGpu(_noBrackets), (
        name: 'Intel HD Graphics 620',
        vendor: 'Intel',
      ));
    });

    test('no graphics line: nothing', () {
      expect(lspciGpu('00:1f.3 Audio device: Intel Corporation\n'), isNull);
      expect(lspciGpu(''), isNull);
    });
  });

  test('the driver\'s vendor ids', () {
    expect(vendorFromPciId('0x1002\n'), 'AMD');
    expect(vendorFromPciId('0x10de'), 'Nvidia');
    expect(vendorFromPciId('8086'), 'Intel');
    expect(vendorFromPciId('0x1af4'), 'Unknown');
  });

  test('libdrm names the card by device and revision', () {
    const ids =
        '# List of AMDGPU IDs\n'
        '#\n'
        '1.0.0\n'
        '73A5,\tC0,\tAMD Radeon RX 6950 XT\n'
        '73AE,\t00,\tAMD Radeon Pro V620\n'
        '73AF,\tC0,\tAMD Radeon RX 6900 XT\n';
    expect(
      amdgpuIdsName(ids, device: '0x73af', revision: '0xc0'),
      'AMD Radeon RX 6900 XT',
    );
    expect(
      amdgpuIdsName(ids, device: '0x73af', revision: '0xc1'),
      'AMD Radeon RX 6900 XT',
      reason: 'a revision the list lacks takes the device\'s name',
    );
    expect(amdgpuIdsName(ids, device: '0x7550'), isNull);
  });

  group('the gfx arch from the driver\'s compute topology', () {
    test('ROCm\'s own encoding, with minor and stepping in hex', () {
      expect(gfxFromKfdTargetVersion(100300), 'gfx1030');
      expect(gfxFromKfdTargetVersion(100301), 'gfx1031');
      expect(gfxFromKfdTargetVersion(110001), 'gfx1101');
      expect(gfxFromKfdTargetVersion(120001), 'gfx1201');
      expect(gfxFromKfdTargetVersion(90010), 'gfx90a');
      expect(gfxFromKfdTargetVersion(90012), 'gfx90c');
      expect(gfxFromKfdTargetVersion(90402), 'gfx942');
      expect(gfxFromKfdTargetVersion(0), isNull);
    });

    test('a node\'s properties, as this machine writes them', () {
      expect(
        kfdGfxTargetVersion(
          'simd_count 160\nmax_slots_scratch_cu 32\n'
          'gfx_target_version 100300\nvendor_id 4098\ndevice_id 29615\n',
        ),
        100300,
      );
      expect(
        kfdGfxTargetVersion('gfx_target_version 0\nvendor_id 0\n'),
        isNull,
        reason: 'the processor\'s node',
      );
    });
  });
}
