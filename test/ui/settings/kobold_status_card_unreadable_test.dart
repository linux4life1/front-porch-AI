// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The "Local model" card for a model whose file cannot be read (moved,
// deleted, on a drive that is not there): it said "Reading the model file…"
// for ever. It now says it could not read it, and reads again when the model
// is chosen again.

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

void main() {
  late Directory dir;

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

  Future<void> mount(WidgetTester tester, String model) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = FakeStorageService();
    await storage.backendSettings.setLastUsedModelPath(model);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<KoboldService>.value(
            value: FakeKoboldService(),
          ),
          ChangeNotifierProvider<HardwareService>.value(value: _Hardware()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: KoboldStatusCard(unified: false, reloadChat: () async {}),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a model file that is gone: reading, then could not be read', (
    tester,
  ) async {
    dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('fpai card gone'),
    ))!;
    addTearDown(() => dir.deleteSync(recursive: true));
    await mount(tester, p.join(dir.path, 'Gone-7B-Q4_K_M.gguf'));

    expect(find.text('Reading the model file…'), findsOneWidget);
    await settle(
      tester,
      () => find.text('Reading the model file…').evaluate().isEmpty,
    );
    expect(
      find.textContaining('The model file could not be read.'),
      findsOneWidget,
    );
    expect(find.textContaining('Still finding out'), findsNothing);
  });

  testWidgets('a file that is not a model says the same', (tester) async {
    dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('fpai card notgguf'),
    ))!;
    addTearDown(() => dir.deleteSync(recursive: true));
    final notModel = File(p.join(dir.path, 'notes.gguf'))
      ..writeAsStringSync('not a model');
    await mount(tester, notModel.path);
    await settle(
      tester,
      () => find.text('Reading the model file…').evaluate().isEmpty,
    );
    expect(
      find.textContaining('The model file could not be read.'),
      findsOneWidget,
    );
  });
}
