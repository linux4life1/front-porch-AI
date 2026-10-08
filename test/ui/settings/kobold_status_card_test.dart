// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The "Local model" card in auto mode, used as a person would: on the
// original author's machine (a 6 GB GTX 1060, 5.1 GB and 11 GB free) with
// the Qwen3.6 35B MoE model (its real header, grown to its real size).

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
  bool running = false;

  @override
  bool get isRunning => running;
}

void main() {
  late Directory dir;
  late FakeStorageService storage;
  late _Kobold kobold;
  var reloads = 0;

  Future<void> settle(WidgetTester tester, [bool Function()? done]) async {
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
      if (done == null ? i >= 8 : done()) return;
    }
    fail('still not done after 4 seconds');
  }

  Future<void> mount(WidgetTester tester, {String? preset}) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    reloads = 0;
    storage = FakeStorageService();
    kobold = _Kobold();
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('fpai card');
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
      if (preset != null) {
        final file = p.join(dir.path, '$preset.kcpps');
        File(file).writeAsStringSync(
          jsonEncode({
            'model_param': model,
            'contextsize': 32768,
            'gpulayers': -1,
            'autofit': true,
            'autofitpadding': 32,
            'noswa': true,
          }),
        );
        await storage.backendSettings.setActiveKcppsPath(file);
      }
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<KoboldService>.value(value: kobold),
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
          find
              .textContaining('Set up for this computer')
              .evaluate()
              .isNotEmpty ||
          (find.textContaining('Uses your preset').evaluate().isNotEmpty &&
              find.text('Reading the preset…').evaluate().isEmpty),
    );
  }

  testWidgets('it says how the model runs here in plain words, no machinery', (
    tester,
  ) async {
    await mount(tester);
    expect(
      find.textContaining(
        'The model is bigger than your graphics card, so replies come at '
        'about reading pace.',
      ),
      findsOneWidget,
    );
    expect(find.text('Replies on long chats start fast.'), findsOneWidget);
    expect(
      find.text('Going back to another chat takes a moment to catch up.'),
      findsOneWidget,
    );
    for (final word in ['batch', 'Batch', 'layer', 'expert', '8-bit', 'MMQ']) {
      expect(find.textContaining(word), findsNothing, reason: word);
    }
  });

  testWidgets('too big: it names the most that works, and one tap uses it', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('131,072'));
    await tester.pump();
    expect(find.textContaining('Too big for this computer.'), findsOneWidget);
    expect(storage.backendSettings.contextSize, 16384, reason: 'not yet');

    await tester.tap(find.text('Use 65,536 tokens'));
    await settle(tester, () => storage.backendSettings.contextSize == 65536);
    expect(find.textContaining('Too big'), findsNothing);
  });

  testWidgets('keeping a size that is too big asks first', (tester) async {
    await mount(tester);
    await tester.tap(find.text('131,072'));
    await tester.pump();
    await tester.tap(find.text('Keep 131,072 anyway…'));
    await tester.pumpAndSettle();
    expect(find.text('Keep 131,072 tokens?'), findsOneWidget);
    await tester.tap(find.text('Keep it'));
    await settle(tester, () => storage.backendSettings.contextSize == 131072);
  });

  testWidgets('below 16,384 is allowed, and warned about', (tester) async {
    await mount(tester);
    await tester.tap(find.text('8,192'));
    await settle(tester, () => storage.backendSettings.contextSize == 8192);
    expect(
      find.textContaining('Not recommended or supported.'),
      findsOneWidget,
    );
  });

  testWidgets('with KoboldCpp running, a few quick changes reload it once', (
    tester,
  ) async {
    await mount(tester);
    kobold.running = true;
    await tester.tap(find.text('32,768'));
    await settle(tester, () => storage.backendSettings.contextSize == 32768);
    await tester.tap(find.text('16,384'));
    await settle(tester, () => storage.backendSettings.contextSize == 16384);
    expect(reloads, 0, reason: 'waits for the user to stop');
    await tester.pump(const Duration(seconds: 2));
    expect(reloads, 1);
  });

  testWidgets('with a preset in use it says what the preset does', (
    tester,
  ) async {
    await mount(tester, preset: 'Long chats');
    expect(find.text('Uses your preset "Long chats".'), findsOneWidget);
    expect(
      find.textContaining('lets KoboldCpp fit it to your card'),
      findsOneWidget,
    );
    expect(find.textContaining('32,768 tokens of chat'), findsOneWidget);
  });
}
