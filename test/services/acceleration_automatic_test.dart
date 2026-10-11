// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Acceleration is worked out from the card. A CUDA, Vulkan, Metal or
// CPU-only pick saved by an older build is dropped when the settings load,
// so nobody is left on a forced backend they cannot see or change. ROCm,
// the one choice the app still offers, is kept.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/storage_service.dart';

import 'storage_service_test.dart'
    show createStorageService, setupPathProviderMock;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  List<bool?> switches(StorageService svc) {
    final b = svc.backendSettings;
    return [b.useCublas, b.useVulkan, b.useMetal, b.useRocm];
  }

  test('a forced Vulkan pick from before loads as automatic', () async {
    final svc = await createStorageService({
      'use_cublas': false,
      'use_vulkan': true,
      'use_metal': false,
      'use_rocm': false,
    });
    expect(switches(svc), [null, null, null, null]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('use_vulkan'), isFalse);
    expect(prefs.containsKey('use_rocm'), isFalse);
  });

  test('CPU only from before (all four off) loads as automatic', () async {
    final svc = await createStorageService({
      'use_cublas': false,
      'use_vulkan': false,
      'use_metal': false,
      'use_rocm': false,
    });
    expect(switches(svc), [null, null, null, null]);
  });

  test('ROCm switched on is kept, and only ROCm', () async {
    final svc = await createStorageService({
      'use_cublas': false,
      'use_vulkan': false,
      'use_metal': false,
      'use_rocm': true,
    });
    expect(switches(svc), [null, null, null, true]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('use_rocm'), isTrue);
    expect(prefs.containsKey('use_vulkan'), isFalse);
  });
}
