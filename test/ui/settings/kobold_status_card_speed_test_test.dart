// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The Local model card in auto mode with the speed test: the button sits
// under the context, and the card judges each context size with what the
// speed test measured for this model, as a launch runs it. Measured on this
// card, flash attention off makes 65,536 tokens too big for a 16 GB card for
// Llama 3.1 8B (its working memory grows with the chat without it), where
// with auto mode's own settings it is only a little slower: tapping it then
// asks "keep anyway" instead of taking it. The model is a real header grown
// to its real size; the preset is written by the app's own writer.

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

const _card = 'NVIDIA GeForce RTX 4080';

class _Storage extends FakeStorageService {
  _Storage(this._bin);
  final Directory _bin;

  @override
  Directory get binDir => _bin;
}

class _Hardware extends FakeHardwareService {
  _Hardware()
    : super(
        hardwareInfo: HardwareInfo(
          gpuName: _card,
          vramMb: 16376,
          ramMb: 32768,
          vendor: 'Nvidia',
          hasCuda: true,
        ),
      );

  FreeMemoryMb? _free = (graphics: 16000, system: 28000);

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
  late _Storage storage;
  late String model;

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

  /// The card on Llama 3.1 8B at 32,768 tokens, on a 16 GB NVIDIA card, with
  /// a measured preset for it when [flashOff] says what it measured.
  Future<void> mount(WidgetTester tester, {bool? flashOff}) async {
    await tester.binding.setSurfaceSize(const Size(900, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('fpai card speed test');
      storage = _Storage(dir);
      const fx = 'test/fixtures/gguf_headers/Llama-3.1-8B';
      final side = jsonDecode(File('$fx.json').readAsStringSync()) as Map;
      model = p.join(dir.path, 'Llama-3.1-8B-Instruct-Q4_K_M.gguf');
      final raf = await File(model).open(mode: FileMode.write);
      await raf.writeFrom(File('$fx.gguf').readAsBytesSync());
      await raf.setPosition((side['fixture_file_bytes'] as int) - 1);
      await raf.writeByte(0);
      await raf.close();
      await storage.backendSettings.setLastUsedModelPath(model);
      await storage.backendSettings.setContextSize(32768);
      if (flashOff != null) {
        final path = await KcppsLibrary(dir.path).write(
          koboldMeasuredPresetName(model, _card),
          kcppsMap(
            KoboldLaunchConfig(
              modelPath: model,
              contextSize: 32768,
              flashAttention: !flashOff,
              backend: KoboldGpuBackend.cuda,
              gpuId: 0,
              measured: const KoboldMeasured(
                card: _card,
                backend: 'cuda',
                engine: '1.122.1',
                auto: true,
              ),
            ),
          ),
        );
        await storage.presetSettings.setModelPreset(model, path);
      }
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    final test = KoboldSpeedTest(
      kobold: _Kobold(),
      why: () async => null,
      setup: () async => null,
      mapFor: (k) async => {},
      loadTrial: (name, config) async => true,
      reloadChat: () async => null,
      save: (s, best) async {},
      replaces: (s) async => null,
    );
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
                reloadChat: () async {},
                speedTest: test,
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
    // The measured preset is read after the first facts.
    await settle(tester, () => true);
  }

  Future<void> pick64k(WidgetTester tester) async {
    await tester.tap(find.text('65,536'));
    await settle(tester, () => true);
  }

  testWidgets('the button sits under the context, with no settings named', (
    tester,
  ) async {
    await mount(tester);
    expect(
      find.text('Find the fastest settings for this computer'),
      findsOneWidget,
    );
    expect(find.textContaining('batch'), findsNothing);
    expect(find.textContaining('MMQ'), findsNothing);
  });

  testWidgets("auto mode's own settings: 65,536 is taken", (tester) async {
    await mount(tester);
    await pick64k(tester);
    expect(storage.backendSettings.contextSize, 65536);
    expect(find.text('Keep 65,536 anyway…'), findsNothing);
  });

  testWidgets('measured with flash attention off: 65,536 is too big, as the '
      'launch would run it, and is asked about first', (tester) async {
    await mount(tester, flashOff: true);
    await pick64k(tester);
    expect(storage.backendSettings.contextSize, 32768);
    expect(find.text('Keep 65,536 anyway…'), findsOneWidget);
  });
}
