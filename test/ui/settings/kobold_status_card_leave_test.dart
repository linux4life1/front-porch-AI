// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The "Local model" card waits for the user to stop tapping before it makes
// KoboldCpp load the new context. Leaving Settings during that wait used to
// cancel the load: the new context was saved, but a running KoboldCpp kept
// the old one until something else restarted it.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/settings/tabs/backend/kobold_status_card.dart';

import '../../golden/support/fakes_services.dart';
import '../../golden/support/fakes_storage.dart';

class _Hardware extends FakeHardwareService {
  _Hardware()
    : super(
        hardwareInfo: HardwareInfo(
          gpuName: 'NVIDIA GeForce GTX 1060 6GB',
          vramMb: 6144,
          ramMb: 16384,
          vendor: 'Nvidia',
          hasCuda: true,
        ),
      );

  FreeMemoryMb? _free = (graphics: 5222, system: 11063);

  @override
  FreeMemoryMb? get freeBeforeEngine => _free;

  @override
  set freeBeforeEngine(FreeMemoryMb? value) => _free = value;
}

class _Kobold extends FakeKoboldService {
  @override
  bool get isRunning => true;
}

void main() {
  late Directory dir;
  late FakeStorageService storage;
  var reloads = 0;

  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
      if (done()) return;
    }
    fail('still not done after 4 seconds');
  }

  Future<void> mount(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    reloads = 0;
    storage = FakeStorageService();
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('fpai card leave');
      const fx = 'test/fixtures/gguf_headers/Llama-3.2-3B';
      final side = jsonDecode(File('$fx.json').readAsStringSync()) as Map;
      final model = p.join(dir.path, 'Llama-3.2-3B-Instruct-Q4_K_M.gguf');
      final raf = await File(model).open(mode: FileMode.write);
      await raf.writeFrom(File('$fx.gguf').readAsBytesSync());
      await raf.setPosition((side['fixture_file_bytes'] as int) - 1);
      await raf.writeByte(0);
      await raf.close();
      await storage.backendSettings.setLastUsedModelPath(model);
      await storage.backendSettings.setContextSize(16384);
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<KoboldService>.value(value: _Kobold()),
          ChangeNotifierProvider<HardwareService>.value(value: _Hardware()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: KoboldStatusCard(
                unified: false,
                reloadChat: () async => reloads++,
              ),
            ),
          ),
        ),
      ),
    );
    await settle(
      tester,
      () =>
          find.textContaining('Set up for this computer').evaluate().isNotEmpty,
    );
  }

  testWidgets('leaving the page before the wait is over still loads the new '
      'context, once', (tester) async {
    await mount(tester);
    await tester.tap(find.text('32,768'));
    await settle(tester, () => storage.backendSettings.contextSize == 32768);
    expect(reloads, 0, reason: 'waits for the user to stop');

    // Settings is closed: the card goes.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(reloads, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(reloads, 1, reason: 'not again when the wait would have ended');
  });

  testWidgets('leaving with nothing waiting loads nothing', (tester) async {
    await mount(tester);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(reloads, 0);
  });
}
