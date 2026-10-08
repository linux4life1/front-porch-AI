// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// At start-up the manager's first look for the engine can run before the
// storage has its data root; the gate must wait for a look that had one, or
// an engine below the floor would be missed on exactly the start the red
// box exists for.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/backend_manager.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:path/path.dart' as p;

import '../kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

class _Manager extends BackendManager {
  _Manager(super.storage)
    : super(onMac: Platform.isMacOS, readArch: () async => 'arm64');
  @override
  Future<void> checkForUpdates() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  test('the gate waits for the storage root, so an old engine is seen on '
      'the first start', () async {
    // The closet, found through a storage that is ready.
    final ready = await createStorageService();
    final bin = ready.binDir;
    await bin.create(recursive: true);
    addTearDown(() => bin.delete(recursive: true));
    final engine = File(p.join(bin.path, _executableName()));
    engine.writeAsBytesSync(List.filled(2048, 1));
    await KoboldBinaryVersion.write(bin.path, version: '1.100', size: 2048);
    ready.dispose();

    // The app's own order: the manager is built while the storage is still
    // initializing, and asks before either has finished.
    final storage = StorageService();
    final manager = _Manager(storage);
    addTearDown(manager.dispose);
    final gate = await manager.updateGate(autoCheck: false);
    expect(gate, KoboldUpdateGate.tooOld);
    expect(manager.backendPath, engine.path);
  });
}

String _executableName() {
  if (Platform.isWindows) return 'koboldcpp.exe';
  if (Platform.isMacOS) return 'koboldcpp-mac-arm64';
  return 'koboldcpp-linux-x64-nocuda';
}
