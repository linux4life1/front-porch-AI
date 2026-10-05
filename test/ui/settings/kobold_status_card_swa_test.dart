// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The "Local model" card with a preset in use. A preset that never mentions
// sliding window, on a model that has it, is left to KoboldCpp's own default,
// which switches sliding window on together with fast forward: a pairing
// that degrades output. The card described that preset as one that "starts
// replies fast on long chats" and said nothing else, so only the engine log
// knew. Now it says the app's sentence too. Real model headers (grown to
// their real size): Gemma 3 has a sliding window, Llama 3.2 has not.

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
  late Directory dir;

  /// The card with [preset] in use on the model of header [fixture].
  Future<void> mount(
    WidgetTester tester, {
    required String fixture,
    required Map<String, dynamic> preset,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = FakeStorageService();
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('fpai card swa');
      const headers = 'test/fixtures/gguf_headers';
      final side =
          jsonDecode(File('$headers/$fixture.json').readAsStringSync()) as Map;
      final model = p.join(dir.path, '$fixture-Q4_K_M.gguf');
      final raf = await File(model).open(mode: FileMode.write);
      await raf.writeFrom(File('$headers/$fixture.gguf').readAsBytesSync());
      await raf.setPosition((side['fixture_file_bytes'] as int) - 1);
      await raf.writeByte(0);
      await raf.close();
      await storage.backendSettings.setLastUsedModelPath(model);
      final file = p.join(dir.path, 'Mine.kcpps');
      File(file).writeAsStringSync(
        jsonEncode({
          'model_param': model,
          'contextsize': 16384,
          'gpulayers': -1,
          'autofit': true,
          ...preset,
        }),
      );
      await storage.backendSettings.setActiveKcppsPath(file);
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
    // The preset and the model's header are read from disk, one after the
    // other.
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(find.textContaining('Uses your preset'), findsOneWidget);
  }

  Finder words() => find.byKey(const ValueKey('local-model-preset-words'));

  String shown(WidgetTester tester) => tester.widget<Text>(words()).data!;

  testWidgets('a preset that says nothing about sliding window, on a model '
      'that has it, says what KoboldCpp will do', (tester) async {
    await mount(tester, fixture: 'gemma-3-12b-it', preset: {});

    expect(shown(tester), contains(kSwaLeftToKoboldNote));
  });

  for (final answered in <Map<String, dynamic>>[
    {'noswa': true},
    {'noswa': false, 'nofastforward': true},
    {'useswa': true, 'nofastforward': true},
  ]) {
    testWidgets('a preset that answers it ($answered) says nothing more', (
      tester,
    ) async {
      await mount(tester, fixture: 'gemma-3-12b-it', preset: answered);

      expect(shown(tester), isNot(contains('sliding window')));
    });
  }

  testWidgets('a model without a sliding window has nothing to warn about', (
    tester,
  ) async {
    await mount(tester, fixture: 'Llama-3.2-3B', preset: {});

    expect(shown(tester), isNot(contains('sliding window')));
  });

  testWidgets('with fast forward off already, there is no pairing to warn '
      'about', (tester) async {
    await mount(
      tester,
      fixture: 'gemma-3-12b-it',
      preset: {'nofastforward': true},
    );

    expect(shown(tester), isNot(contains('sliding window')));
  });
}
