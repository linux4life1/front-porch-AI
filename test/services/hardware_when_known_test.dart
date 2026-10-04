// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A launch with no graphics backend ever chosen needs to know the card. On
// a first run the answer may not be in yet, and the launch used to go ahead
// on the CPU. `whenKnown` waits for it, within a limit.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/hardware_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an answer that is still being restored is waited for', () async {
    final cached = jsonEncode(
      HardwareInfo(
        gpuName: 'NVIDIA GeForce RTX 4070',
        vramMb: 12288,
        ramMb: 32768,
        vendor: 'Nvidia',
        hasCuda: true,
        hasRocm: false,
        hasMetal: false,
        isSharedMemory: false,
        linuxDistro: 'arch',
      ).toJson(),
    );
    SharedPreferences.setMockInitialValues({
      'hardware_info_cache': cached,
      'beta_hardware_info_cache': cached,
    });
    final service = HardwareService();
    addTearDown(service.dispose);

    // Nothing is known the instant the service is made.
    expect(service.hardwareInfo, isNull);
    final known = await service.whenKnown();
    expect(known?.hasCuda, isTrue);
    expect(known?.vendor, 'Nvidia');
  });

  test('with nothing known and no answer coming, the wait ends at its limit '
      'and the caller goes on without it', () async {
    // No answer can come: with the test binding the service holds its
    // detection for a first frame, and a plain test never draws one.
    SharedPreferences.setMockInitialValues({});
    final service = HardwareService();
    addTearDown(service.dispose);

    final waited = Stopwatch()..start();
    final known = await service.whenKnown(
      timeout: const Duration(milliseconds: 80),
    );
    expect(known, isNull);
    expect(waited.elapsedMilliseconds, greaterThanOrEqualTo(70));
  });
}
