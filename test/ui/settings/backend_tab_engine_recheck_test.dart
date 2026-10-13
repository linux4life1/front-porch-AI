// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Settings → Backend opened after the KoboldCpp engine file was removed.
// It used to say "Ready" with the old path until Start was pressed, because
// nothing looked for the engine again when the tab opened.
//
// The real Settings page over the real BackendManager (told it is on Linux)
// and a real engine file in the data root's bin folder.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/pages.dart';

import '../../helpers/settings_page_harness.dart';

class _RootedStorage extends SettingsPageStorage {
  _RootedStorage(super.bin, this.root);

  final String root;

  @override
  String? get rootPath => root;

  @override
  Future<void> get initialized => Future.value();
}

class _LinuxManager extends BackendManager {
  _LinuxManager(super.storage)
    : super(onLinux: true, onMac: false, readArch: () async => 'x86_64');
  @override
  Future<void> checkForUpdates() async {}
}

void main() {
  testWidgets('opening the Backend tab after the engine file is removed '
      'shows it missing', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});

    late SettingsPageRig rig;
    late File engine;
    late _LinuxManager engines;
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('fpai engine recheck');
      final bin = await Directory(p.join(dir.path, 'bin')).create();
      engine = File(p.join(bin.path, 'koboldcpp-linux-x64-nocuda'));
      await engine.writeAsBytes(List.filled(2048, 1));
      final a = await writeGgufModel(dir, 'Llama-3.1-8B', 'a-Llama.gguf');
      final store = _RootedStorage(bin, dir.path);
      await store.backendSettings.setBackendType('kobold');
      await store.backendSettings.setUseVulkan(true);
      final kobold = RecordingKobold(store);
      rig = SettingsPageRig(
        dir: dir,
        store: store,
        kobold: kobold,
        llm: ReloadCountingLlm(kobold),
        a: a,
        b: a,
      );
      rig.models = ListedModels([a]);
      rig.backend = ReadyBackendManager(engine.path);
      engines = _LinuxManager(store);
      await engines.engineChecked;
    });
    addTearDown(() {
      engines.dispose();
      rig.kobold.dispose();
      rig.dir.deleteSync(recursive: true);
    });
    expect(engines.backendPath, engine.path, reason: 'found at start-up');

    await tester.pumpWidget(
      withRigProviders(
        rig,
        child: ChangeNotifierProvider<BackendManager>.value(
          value: engines,
          child: const MaterialApp(home: SettingsPage()),
        ),
      ),
    );
    await settle(tester);

    await tester.runAsync(engine.delete);
    await openTab(tester, 'Backend');
    await settle(tester, () => engines.backendPath == null);

    expect(find.textContaining('Status: Ready'), findsNothing);
    expect(find.text('Status: Missing'), findsOneWidget);
  });
}
