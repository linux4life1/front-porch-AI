// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The desktop "Local model" card in auto mode offers context up to the
// length the model was made for: an 8k model no longer gets 32k to 131k as
// if they were fine (it gets 8,192 and the size in use, with a plain
// warning), and a model made for 262,144 tokens is offered all of it. Real
// model files: Llama 3.2's header saying 8,192, and Qwen3.6 35B.

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
import '../../helpers/short_model_file.dart';

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
  late Directory dir;

  /// The card in auto mode on the model [write] puts in the folder.
  Future<void> mount(
    WidgetTester tester,
    Future<String> Function(Directory dir) write,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = FakeStorageService();
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('fpai card ceiling');
      await storage.backendSettings.setLastUsedModelPath(await write(dir));
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
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(find.byKey(const ValueKey('local-model-context')), findsOneWidget);
  }

  Finder chip(String label) => find.descendant(
    of: find.byKey(const ValueKey('local-model-context')),
    matching: find.text(label),
  );

  Finder warning() => find.byKey(const ValueKey('local-model-short-model'));

  testWidgets('an 8k model: 8,192 and the size in use, and a plain warning', (
    tester,
  ) async {
    await mount(tester, (dir) => writeShortModel(dir, contextLength: 8192));

    expect(chip('8,192'), findsOneWidget);
    expect(chip('16,384'), findsOneWidget);
    for (final more in ['32,768', '65,536', '131,072']) {
      expect(chip(more), findsNothing, reason: more);
    }
    expect(warning(), findsOneWidget);
    expect(
      find.descendant(
        of: warning(),
        matching: find.textContaining('This model was made for 8,192 tokens'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a model made for 262,144 tokens is offered all of it, with no '
      'warning', (tester) async {
    await mount(tester, (dir) async {
      const fx = 'test/fixtures/gguf_headers/Qwen3.6-35B-A3B-Q4_K_XL';
      final side = jsonDecode(File('$fx.json').readAsStringSync()) as Map;
      final model = p.join(dir.path, 'Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf');
      final raf = await File(model).open(mode: FileMode.write);
      await raf.writeFrom(File('$fx.gguf').readAsBytesSync());
      await raf.setPosition((side['fixture_file_bytes'] as int) - 1);
      await raf.writeByte(0);
      await raf.close();
      return model;
    });

    expect(chip('131,072'), findsOneWidget);
    expect(chip('262,144'), findsOneWidget);
    expect(warning(), findsNothing);
  });
}
