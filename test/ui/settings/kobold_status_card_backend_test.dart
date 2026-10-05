// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The "Local model" card in auto mode follows the backend the user chose in
// Settings: it is worked out again when a switch changes, and says what that
// backend does with the model. (The card keeps what it worked out between
// rebuilds, keyed by what it read; a switch that was left out of the key
// left a stale card on screen after "CPU only" was chosen.)

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

void main() {
  testWidgets('choosing "CPU only" in Settings changes what the card says, '
      'and going back to automatic changes it back', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = FakeStorageService();
    late Directory dir;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('fpai card backend');
      const fx = 'test/fixtures/gguf_headers/Qwen3.6-35B-A3B-Q4_K_XL';
      final side = jsonDecode(File('$fx.json').readAsStringSync()) as Map;
      final model = p.join(dir.path, 'Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf');
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

    Future<void> until(Finder what) async {
      for (var i = 0; i < 200 && what.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(what, findsOneWidget);
    }

    final card = find.textContaining('about reading pace');
    final noCard = find.textContaining('no graphics card it can use');
    await until(card);

    // The chips write all four switches: off, for "CPU only".
    final b = storage.backendSettings;
    await tester.runAsync(() async {
      await b.setUseCublas(false);
      await b.setUseVulkan(false);
      await b.setUseRocm(false);
      await b.setUseMetal(false);
    });
    await tester.pump();
    await until(noCard);
    expect(card, findsNothing);

    // "Reset to Automatic" clears all four.
    await tester.runAsync(() async {
      await b.setUseCublas(null);
      await b.setUseVulkan(null);
      await b.setUseRocm(null);
      await b.setUseMetal(null);
    });
    await tester.pump();
    await until(card);
    expect(noCard, findsNothing);
  });
}
