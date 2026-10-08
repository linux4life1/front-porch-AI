// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The desktop "Local model" card follows "Set layers myself": switched on in
// Advanced settings, the card says "Set up by hand in Advanced settings."
// with the speed of the layer count set, and the verdicts move with it; off
// again, it is back to automatic. The card works its facts out once per
// change of what they read, so the layer settings have to be among them.
// The phone reads the same facts (local_model_manual_layers_test.dart).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/settings/tabs/backend/backend.dart';

import '../../golden/support/fakes_services.dart';
import '../../golden/support/fakes_storage.dart';

class _Hardware extends FakeHardwareService {
  _Hardware()
    : super(
        hardwareInfo: HardwareInfo(
          gpuName: 'NVIDIA GeForce RTX 4090',
          vramMb: 24564,
          ramMb: 65536,
          vendor: 'Nvidia',
          hasCuda: true,
        ),
      );

  @override
  FreeMemoryMb? get freeBeforeEngine => (graphics: 23000, system: 60000);

  @override
  set freeBeforeEngine(FreeMemoryMb? value) {}
}

void main() {
  testWidgets('switching "Set layers myself" on and off changes what the '
      'card says', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = FakeStorageService();
    final b = storage.backendSettings;
    late Directory dir;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('fpai card manual');
      const fx = 'test/fixtures/gguf_headers/Llama-3.1-8B';
      final side = jsonDecode(File('$fx.json').readAsStringSync()) as Map;
      final model = p.join(dir.path, 'Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf');
      final raf = await File(model).open(mode: FileMode.write);
      await raf.writeFrom(File('$fx.gguf').readAsBytesSync());
      await raf.setPosition((side['fixture_file_bytes'] as int) - 1);
      await raf.writeByte(0);
      await raf.close();
      await b.setLastUsedModelPath(model);
      await b.setContextSize(16384);
      await b.setGpuLayers(10);
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
    Future<void> settle() async {
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
    }

    await settle();
    expect(find.textContaining('Set up for this computer'), findsOneWidget);
    expect(find.textContaining('replies come quickly'), findsOneWidget);

    await tester.runAsync(() => b.setGpuLayersManual(true));
    await settle();
    expect(
      find.text(
        'Set up by hand in Advanced settings. Much of the model runs from '
        'system memory, so replies come slowly.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Set up for this computer'), findsNothing);

    await tester.runAsync(() => b.setGpuLayersManual(false));
    await settle();
    expect(find.textContaining('Set up for this computer'), findsOneWidget);
  });
}
