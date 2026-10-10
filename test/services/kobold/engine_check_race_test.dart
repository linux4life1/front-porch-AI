// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Two engine checks at once. A settings change re-runs the check while an
// earlier one is still reading the engine's version; if the later one finds
// no engine it clears the shared path, and the earlier one used to crash on
// it ("Null check operator used on a null value") when it went on to mark the
// file executable. Seen on CI from the ROCm engine-version test.
//
// The manager is the real one, told it is on Linux; the engine is a real file.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/backend_manager.dart';
import 'package:front_porch_ai/services/storage_service.dart';

import '../kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

class _LinuxManager extends BackendManager {
  _LinuxManager(super.storage)
    : super(onLinux: true, onMac: false, readArch: () async => 'x86_64');
  @override
  Future<void> checkForUpdates() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();
  late StorageService storage;
  late Directory bin;

  setUp(() async {
    storage = await createStorageService();
    bin = storage.binDir;
    if (bin.existsSync()) bin.deleteSync(recursive: true);
    await bin.create(recursive: true);
    await storage.backendSettings.setUseVulkan(true);
  });
  tearDown(() {
    if (bin.existsSync()) bin.deleteSync(recursive: true);
  });

  test('a check that loses its engine mid-way does not crash the one '
      'still reading it', () async {
    final engine = File(p.join(bin.path, 'koboldcpp-linux-x64-nocuda'));
    await engine.writeAsBytes(List.filled(2048, 1));
    final m = _LinuxManager(storage);
    addTearDown(m.dispose);
    await m.engineChecked;

    for (var round = 0; round < 20; round++) {
      if (!engine.existsSync()) await engine.writeAsBytes(List.filled(2048, 1));
      final first = m.checkBackendAvailability();
      // Let the first look find the file, then take it away before the
      // second look runs.
      await Future<void>.delayed(Duration.zero);
      await engine.delete();
      final second = m.checkBackendAvailability();
      await Future.wait([first, second]);
    }
    expect(m.backendPath, isNull, reason: 'the engine is gone at the end');
  });
}
