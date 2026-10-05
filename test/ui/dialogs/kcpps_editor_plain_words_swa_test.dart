// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The preset editor's "In plain words" for a preset that leaves sliding
// window to KoboldCpp, on a model that has one, with fast forward on. The
// desktop's Local model card and the phone's cards say what KoboldCpp then
// does (kSwaLeftToKoboldNote) in those same plain words; the editor's panel
// said only "starts replies fast on long chats", as if sliding window were
// off. Now it says the sentence too, and stops once the switch is answered.
//
// The whole dialog, real model header (Gemma 3 has a sliding window).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/kcpps_editor/kcpps_editor.dart';
import 'package:front_porch_ai/utils/utils.dart';

import '../../golden/support/fakes_services.dart';
import '../../golden/support/fakes_storage.dart';

class _Storage extends FakeStorageService {
  _Storage(this._bin);
  final Directory _bin;

  @override
  Directory get binDir => _bin;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory bin;
  late String gemma;
  late KcppsEditorController c;

  setUp(() async {
    bin = await Directory.systemTemp.createTemp('fpai editor plain words');
    gemma = p.join(bin.path, 'gemma-3-12b-it-Q4_K_M.gguf');
    final info = await GGUFParser.getModelArchitectureInfo(
      'test/fixtures/gguf_headers/gemma-3-12b-it.gguf',
    );
    c = KcppsEditorController(
      storage: _Storage(bin),
      hardware: FakeHardwareService(
        hardwareInfo: HardwareInfo(
          gpuName: 'NVIDIA GeForce RTX 4090',
          vramMb: 24564,
          ramMb: 65536,
          vendor: 'Nvidia',
          hasCuda: true,
        ),
      ),
      kobold: FakeKoboldService(),
      readFree: () async => (graphics: 23000, system: 60000),
      readModel: (path) async => (info: info, bytes: 0),
      unified: false,
      threads: () async => 8,
    );
  });

  tearDown(() async {
    c.dispose();
    await bin.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester, Map<String, dynamic> written) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await File(p.join(bin.path, 'Mine.kcpps')).writeAsString(
        jsonEncode({'model_param': gemma, 'contextsize': 16384, ...written}),
      );
      await c.init();
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: c.storage,
        child: MaterialApp(
          home: Scaffold(body: KcppsEditorDialog(controller: c)),
        ),
      ),
    );
    await tester.pump();
  }

  /// The words in the "In plain words" panel.
  String plain(WidgetTester tester) =>
      tester.widget<KcppsPlainWords>(find.byType(KcppsPlainWords)).text;

  testWidgets('a preset that says nothing about it: the plain words say what '
      'KoboldCpp does, as the cards do', (tester) async {
    await mount(tester, {});

    expect(plain(tester), contains(kSwaLeftToKoboldNote));
  });

  testWidgets('answered, or with fast forward off, they do not', (
    tester,
  ) async {
    for (final written in <Map<String, dynamic>>[
      {'noswa': true},
      {'nofastforward': true},
    ]) {
      await mount(tester, written);

      expect(
        plain(tester),
        isNot(contains(kSwaLeftToKoboldNote)),
        reason: '$written',
      );
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('answering the switch takes the sentence out of them', (
    tester,
  ) async {
    await mount(tester, {});

    await tester.tap(find.text('Sliding window: left to KoboldCpp'));
    await tester.pump();

    expect(plain(tester), isNot(contains(kSwaLeftToKoboldNote)));
  });
}
